module L = Llvm
module A = Ast
open Sast

module StringMap = Map.Make(String)

let translate (globals, functions) =
	let context = L.global_context () in
	(* Create the LLVM compilation module into which
	we will generate code *)
	let the_module = L.create_module context "GVL" in

	let i32_t      = L.i32_type    context in

	let ltype_of_typ = function
	    A.Int -> i32_t
	in

  (* Define each function (arguments and return type) so we can 
     call it even before we've created its body *)
  let function_decls : (L.llvalue * sfunc_decl) StringMap.t =
    let function_decl m fdecl =
      let name = fdecl.sfname
      and formal_types = 
				Array.of_list (List.map (fun (t,_) -> ltype_of_typ t) fdecl.sformals)
      in let ftype = L.function_type (ltype_of_typ fdecl.styp) formal_types in
      StringMap.add name (L.define_function name ftype the_module, fdecl) m in
    List.fold_left function_decl StringMap.empty functions in

	let build_function_body fdecl =
	  (* TODO *)
    let (the_function, _) = StringMap.find fdecl.sfname function_decls in
    let builder = L.builder_at_end context (L.entry_block the_function) in

	  let rec expr builder ((_, e) : sexpr) = match e with
	      SBinop (e1, op, e2) ->
		      let e1' = expr builder e1
		      and e2' = expr builder e2 in
		      (match op with
					  A.Add     -> L.build_add
					| A.Sub     -> L.build_sub
					| A.Mul     -> L.build_mul
				  | A.Div     -> L.build_sdiv
				  | A.Mod     -> L.build_srem
					| A.And     -> L.build_and
					| A.Or      -> L.build_or
					| A.Equal   -> L.build_icmp L.Icmp.Eq
					| A.Neq     -> L.build_icmp L.Icmp.Ne
					| A.Less    -> L.build_icmp L.Icmp.Slt
					| A.Leq     -> L.build_icmp L.Icmp.Sle
					| A.Greater -> L.build_icmp L.Icmp.Sgt
					| A.Geq     -> L.build_icmp L.Icmp.Sge
		      ) e1' e2' "tmp" builder
	    | SUnop(op, e) ->
	        let e' = expr builder e in
	        (match op with
	          A.Neg -> L.build_neg
	        | A.Not -> L.build_not) e' "tmp" builder
	    (*
	    | SAssign (v, e) -> let e' = expr builder e in
                          ignore(L.build_store e' (lookup s) builder); e'
	    | SCall (f, args) -> raise (Failure "codegen expr scall not implemented")
	    | SId s -> L.build_load (lookup s) s builder*)
	    | SIntLit i -> L.const_int i32_t i
	  in

    let add_terminal builder instr =
      match L.block_terminator (L.insertion_block builder) with
				Some _ -> ()
      | None -> ignore (instr builder) in

    let rec stmt builder = function
				SBlock sl -> List.fold_left stmt builder sl
      | SExpr e -> ignore(expr builder e); builder
    in

    let builder = stmt builder (SBlock fdecl.sbody) in

    add_terminal builder (L.build_ret (L.const_int (ltype_of_typ fdecl.styp) 0))
	(* ... *)
	in
	List.iter build_function_body functions;
	the_module
