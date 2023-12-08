(** {!GoblintCil} utilities. *)

open GobConfig
open GoblintCil
module E = Errormsg

include Cilfacade0

(** Command for assigning an id to a varinfo. All varinfos directly created by Goblint should be modified by this method *)
let create_var (var: varinfo) =
  (* TODO Hack: this offset should preempt conflicts with ids generated by CIL *)
  let start_id = 10_000_000_000 in
  let hash = Hashtbl.hash { var with vid = 0 } in
  let hash = if hash < start_id then hash + start_id else hash in
  { var with vid = hash }


(** Is character type (N1570 6.2.5.15)? *)
let isCharType t =
  match Cil.unrollType t with
  | TInt ((IChar | ISChar | IUChar), _) -> true
  | _ -> false

let isFloatType t =
  match Cil.unrollType t with
  | TFloat _ -> true
  | _ -> false

let rec isVLAType t =
  match Cil.unrollType t with
  | TArray (et, len, _) ->
    let variable_len = GobOption.exists (Fun.negate Cil.isConstant) len in
    variable_len || isVLAType et
  | _ -> false

let is_first_field x = match x.fcomp.cfields with
  | [] -> false
  | f :: _ -> CilType.Fieldinfo.equal f x

let init_options () =
  Mergecil.merge_inlines := get_bool "cil.merge.inlines";
  Cil.cstd := Cil.cstd_of_string (get_string "cil.cstd");
  Cil.gnu89inline := get_bool "cil.gnu89inline";
  Cabs2cil.addNestedScopeAttr := get_bool "cil.addNestedScopeAttr"

let init () =
  initCIL ();
  removeBranchingOnConstants := false;
  addReturnOnNoreturnFallthrough := true;
  lowerConstants := true;
  Mergecil.ignore_merge_conflicts := true;
  (* lineDirectiveStyle := None; *)
  RmUnused.keepUnused := true;
  print_CIL_Input := true;
  Cabs2cil.allowDuplication := false;
  Cabs2cil.silenceLongDoubleWarning := true

let current_file = ref dummyFile

(** @raise GoblintCil.FrontC.ParseError
    @raise GoblintCil.Errormsg.Error *)
let parse fileName =
  let fileName_str = Fpath.to_string fileName in
  Errormsg.hadErrors := false; (* reset because CIL doesn't *)
  let cabs2cil = Timing.wrap ~args:[("file", `String fileName_str)] "FrontC" Frontc.parse fileName_str in
  let file = Timing.wrap ~args:[("file", `String fileName_str)] "Cabs2cil" cabs2cil () in
  if !E.hadErrors then
    E.s (E.error "There were parsing errors in %s" fileName_str);
  file

let print (fileAST: file) =
  dumpFile defaultCilPrinter stdout "stdout" fileAST

let rmTemps fileAST =
  RmUnused.removeUnused fileAST

let visitors = ref []
let register_preprocess name visitor_fun =
  visitors := !visitors @ [name, visitor_fun]

let do_preprocess ast =
  (* this has to be done here, since the settings aren't available when register_preprocess is called *)
  let active_visitors = List.filter_map (fun (name, visitor_fun) -> if List.mem name (get_string_list "ana.activated") then Some visitor_fun else None) !visitors in
  let f fd visitor_fun = ignore @@ visitCilFunction (visitor_fun fd) fd in
  if active_visitors <> [] then
    iterGlobals ast (function GFun (fd,_) -> List.iter (f fd) active_visitors | _ -> ())
  else
    ()

(** @raise GoblintCil.FrontC.ParseError
    @raise GoblintCil.Errormsg.Error *)
let getAST fileName =
  let fileAST = parse fileName in
  (*  rmTemps fileAST; *)
  fileAST

(* a visitor that puts calls to constructors at the starting points to main *)
class addConstructors cons = object
  inherit nopCilVisitor
  val mutable cons1 = cons
  method! vfunc fd =
    if List.mem fd.svar.vname (get_string_list "mainfun") then begin
      if get_bool "dbg.verbose" then ignore (Pretty.printf "Adding constructors to: %s\n" fd.svar.vname);
      let loc = match fd.sbody.bstmts with
        | s :: _ -> get_stmtLoc s
        | [] -> locUnknown
      in
      let f fd = mkStmt (Instr [Call (None,Lval (Var fd.svar, NoOffset),[],loc,locUnknown)]) in (* TODO: fd declaration loc for eloc? *)
      let call_cons = List.map f cons1 in
      let body = mkBlock (call_cons @ fd.sbody.bstmts) in
      fd.sbody <- body;
      ChangeTo fd
    end else SkipChildren

  method! vstmt _ = SkipChildren
  method! vvdec _ = SkipChildren
  method! vexpr _ = SkipChildren
  method! vlval _ = SkipChildren
  method! vtype _ = SkipChildren
end

(** @raise GoblintCil.Errormsg.Error *)
let getMergedAST fileASTs =
  Errormsg.hadErrors := false; (* reset because CIL doesn't *)
  let merged = Timing.wrap "mergeCIL"  (Mergecil.merge fileASTs) "stdout" in
  if !E.hadErrors then
    E.s (E.error "There were errors during merging\n");
  merged

(* call constructors at start of main functions *)
let callConstructors ast =
  let constructors =
    let cons = ref [] in
    iterGlobals ast (fun glob ->
        match glob with
        | GFun({svar={vattr=attr; _}; _} as def, _) when hasAttribute "constructor" attr ->
          cons := def::!cons
        | _ -> ()
      );
    !cons
  in
  let d_fundec () fd = Pretty.text fd.svar.vname in
  if get_bool "dbg.verbose" then ignore (Pretty.printf "Constructors: %a\n" (Pretty.d_list ", " d_fundec) constructors);
  visitCilFileSameGlobals (new addConstructors constructors) ast;
  ast

let in_section check attr_list =
  let f attr = match attr with
    | Attr ("section", [AStr str]) -> check str
    | _ -> false
  in List.exists f attr_list

let is_init = in_section (fun s -> s = ".init.text")
let is_exit = in_section (fun s -> s = ".exit.text")

type startfuns = fundec list * fundec list * fundec list

let getFuns fileAST : startfuns =
  let add_main f (m,e,o) = (f::m,e,o) in
  let add_exit f (m,e,o) = (m,f::e,o) in
  let add_other f (m,e,o) = (m,e,f::o) in
  let f acc glob =
    match glob with
    | GFun({svar={vname=mn; _}; _} as def,_) when List.mem mn (get_string_list "mainfun") -> add_main def acc
    | GFun({svar={vname=mn; _}; _} as def,_) when List.mem mn (get_string_list "exitfun") -> add_exit def acc
    | GFun({svar={vname=mn; _}; _} as def,_) when List.mem mn (get_string_list "otherfun") -> add_other def acc
    | GFun({svar={vname=mn; vattr=attr; _}; _} as def, _) when get_bool "kernel" && is_init attr ->
      Printf.printf "Start function: %s\n" mn; set_string "mainfun[+]" mn; add_main def acc
    | GFun({svar={vname=mn; vattr=attr; _}; _} as def, _) when get_bool "kernel" && is_exit attr ->
      Printf.printf "Cleanup function: %s\n" mn; set_string "exitfun[+]" mn; add_exit def acc
    | GFun ({svar={vstorage=NoStorage; vattr; _}; _} as def, _) when get_bool "nonstatic" && not (Cil.hasAttribute "goblint_stub" vattr) -> add_other def acc
    | GFun ({svar={vattr; _}; _} as def, _) when get_bool "allfuns" && not (Cil.hasAttribute "goblint_stub" vattr) ->  add_other def  acc
    | _ -> acc
  in
  foldGlobals fileAST f ([],[],[])


let getFirstStmt fd = List.hd fd.sbody.bstmts


(* Returns the ikind of a TInt(_) and TEnum(_). Unrolls typedefs. *)
let rec get_ikind t =
  (* important to unroll the type here, otherwise problems with typedefs *)
  match Cil.unrollType t with
  | TInt (ik,_)
  | TEnum ({ekind = ik; _},_) -> ik
  | TPtr _ -> get_ikind !Cil.upointType
  | _ -> invalid_arg ("Cilfacade.get_ikind: non-integer type " ^ CilType.Typ.show t)

let get_fkind t =
  (* important to unroll the type here, otherwise problems with typedefs *)
  match Cil.unrollType t with
  | TFloat (fk,_) -> fk
  | _ -> invalid_arg ("Cilfacade.get_fkind: non-float type " ^ CilType.Typ.show t)

let ptrdiff_ikind () = get_ikind !ptrdiffType
let ptr_ikind () = match !upointType with TInt (ik,_) -> ik | _ -> assert false

(** Cil.typeOf, etc reimplemented to raise sensible exceptions
    instead of printing all errors directly... *)

type typeOfError =
  | RealImag_NonNumerical (** unexpected non-numerical type for argument to __real__/__imag__ *)
  | StartOf_NonArray (** typeOf: StartOf on a non-array *)
  | Mem_NonPointer of exp (** typeOfLval: Mem on a non-pointer (exp) *)
  | Index_NonArray of exp * typ (** typeOffset: Index on a non-array *)
  | Field_NonCompound of fieldinfo * typ (** typeOffset: Field on a non-compound *)

exception TypeOfError of typeOfError

let () = Printexc.register_printer (function
    | TypeOfError error ->
      let msg = match error with
        | RealImag_NonNumerical -> "unexpected non-numerical type for argument to __real__/__imag__"
        | StartOf_NonArray -> "typeOf: StartOf on a non-array"
        | Mem_NonPointer exp -> Printf.sprintf "typeOfLval: Mem on a non-pointer (%s)" (CilType.Exp.show exp)
        | Index_NonArray (e, typ) -> Printf.sprintf "typeOffset: Index on a non-array (%s, %s)" (CilType.Exp.show e) (CilType.Typ.show typ)
        | Field_NonCompound (fi, typ) -> Printf.sprintf "typeOffset: Field on a non-compound (%s, %s)" (CilType.Fieldinfo.show fi) (CilType.Typ.show typ)
      in
      Some (Printf.sprintf "Cilfacade.TypeOfError(%s)" msg)
    | _ -> None (* for other exceptions *)
  )

(* Cil doesn't expose this *)
let stringLiteralType = ref charPtrType

let typeOfRealAndImagComponents t =
  match unrollType t with
  | TInt _ -> t
  | TFloat (fkind, attrs) ->
    let newfkind = function
      | FFloat -> FFloat      (* [float] *)
      | FDouble -> FDouble     (* [double] *)
      | FLongDouble -> FLongDouble (* [long double] *)
      | FFloat128 -> FFloat128 (* [float128] *)
      | FComplexFloat -> FFloat
      | FComplexDouble -> FDouble
      | FComplexLongDouble -> FLongDouble
      | FComplexFloat128 -> FComplexFloat128
    in
    TFloat (newfkind fkind, attrs)
  | _ -> raise (TypeOfError RealImag_NonNumerical)

let isComplexFKind = function
  | FFloat
  | FDouble
  | FLongDouble
  | FFloat128 -> false
  | FComplexFloat
  | FComplexDouble
  | FComplexLongDouble
  | FComplexFloat128 -> true

let rec typeOf (e: exp) : typ =
  match e with
  | Const(CInt (_, ik, _)) -> TInt(ik, [])

  (* Character constants have type int.  ISO/IEC 9899:1999 (E),
   * section 6.4.4.4 [Character constants], paragraph 10, if you
   * don't believe me. *)
  | Const(CChr _) -> intType

  (* The type of a string is a pointer to characters ! The only case when
   * you would want it to be an array is as an argument to sizeof, but we
   * have SizeOfStr for that *)
  | Const(CStr (s,_)) -> !stringLiteralType

  | Const(CWStr (s,_)) -> TPtr(!wcharType,[])

  | Const(CReal (_, fk, _)) -> TFloat(fk, [])

  | Const(CEnum(tag, _, ei)) -> typeOf tag
  | Real e -> typeOfRealAndImagComponents @@ typeOf e
  | Imag e -> typeOfRealAndImagComponents @@ typeOf e
  | Lval(lv) -> typeOfLval lv
  | SizeOf _ | SizeOfE _ | SizeOfStr _ -> !typeOfSizeOf
  | AlignOf _ | AlignOfE _ -> !typeOfSizeOf
  | UnOp (_, _, t)
  | BinOp (_, _, _, t)
  | Question (_, _, _, t)
  | CastE (t, _) -> t
  | AddrOf (lv) -> TPtr(typeOfLval lv, [])
  | AddrOfLabel (lv) -> voidPtrType
  | StartOf (lv) -> begin
      match unrollType (typeOfLval lv) with
        TArray (t,_, a) -> TPtr(t, a)
      | _ -> raise (TypeOfError StartOf_NonArray)
    end

and typeOfInit (i: init) : typ =
  match i with
    SingleInit e -> typeOf e
  | CompoundInit (t, _) -> t

and typeOfLval = function
    Var vi, off -> typeOffset vi.vtype off
  | Mem addr, off -> begin
      match unrollType (typeOf addr) with
        TPtr (t, _) -> typeOffset t off
      | _ -> raise (TypeOfError (Mem_NonPointer addr))
    end

and typeOffset basetyp =
  let blendAttributes baseAttrs =
    let (_, _, contageous) =
      partitionAttributes ~default:AttrName baseAttrs in
    typeAddAttributes contageous
  in
  function
    NoOffset -> basetyp
  | Index (e, o) -> begin
      match unrollType basetyp with
        TArray (t, _, baseAttrs) ->
        let elementType = typeOffset t o in
        blendAttributes baseAttrs elementType
      | t -> raise (TypeOfError (Index_NonArray (e, t)))
    end
  | Field (fi, o) ->
    match unrollType basetyp with
      TComp (_, baseAttrs) ->
      let fieldType = typeOffset fi.ftype o in
      blendAttributes baseAttrs fieldType
    | t -> raise (TypeOfError (Field_NonCompound (fi, t)))


let typeBlendAttributes baseAttrs = (* copied from Cilfacade.typeOffset *)
  let (_, _, contageous) = partitionAttributes ~default:AttrName baseAttrs in
  typeAddAttributes contageous

let typeSigBlendAttributes baseAttrs =
  let (_, _, contageous) = partitionAttributes ~default:AttrName baseAttrs in
  typeSigAddAttrs contageous


(** {!Cil.mkCast} using our {!typeOf}. *)
let mkCast ~(e: exp) ~(newt: typ) =
  let oldt =
    try
      typeOf e
    with TypeOfError _ -> (* e might involve alloc variables, weird offsets, etc *)
      Cil.voidType (* oldt is only used for avoiding duplicate cast, so this falls back to adding cast *)
  in
  Cil.mkCastT ~e ~oldt ~newt

let get_ikind_exp e = get_ikind (typeOf e)
let get_fkind_exp e = get_fkind (typeOf e)

(** Make {!Cil.BinOp} with correct implicit casts inserted. *)
let makeBinOp binop e1 e2 =
  let t1 = typeOf e1 in
  let t2 = typeOf e2 in
  let (_, e) = Cabs2cil.doBinOp binop e1 t1 e2 t2 in
  e

let anoncomp_name_regexp = Str.regexp {|^__anon\(struct\|union\)\(_\(.+\)\)?_\([0-9]+\)$|}

let split_anoncomp_name name =
  (* __anonunion_pthread_mutexattr_t_488594144 *)
  (* __anonunion_50 *)
  if Str.string_match anoncomp_name_regexp name 0 then (
    let struct_ = match Str.matched_group 1 name with
      | "struct" -> true
      | "union" -> false
      | _ -> assert false
    in
    let name' = try Some (Str.matched_group 3 name) with Not_found -> None in
    let id = int_of_string (Str.matched_group 4 name) in
    (struct_, name', id)
  )
  else
    invalid_arg ("Cilfacade.split_anoncomp_name: " ^ name)

(** Pretty-print typsig like typ, because
    {!d_typsig} prints with CIL constructors. *)
let rec pretty_typsig_like_typ (nameOpt: Pretty.doc option) () ts =
  (* Copied & modified from Cil.defaultCilPrinterClass#pType. *)
  let open Pretty in
  let name = match nameOpt with None -> nil | Some d -> d in
  let printAttributes (a: attributes) =
    let pa = d_attrlist () a in
    match nameOpt with
    | None when not !print_CIL_Input ->
      (* Cannot print the attributes in this case because gcc does not
          like them here, except if we are printing for CIL. *)
      if pa = nil then nil else
        text "/*" ++ pa ++ text "*/"
    | _ -> pa
  in
  match ts with
  | TSBase t -> defaultCilPrinter#pType nameOpt () t
  | TSComp (cstruct, cname, a) ->
    let su = if cstruct then "struct" else "union" in
    text (su ^ " " ^ cname ^ " ")
    ++ d_attrlist () a
    ++ name
  | TSEnum (ename, a) ->
    text ("enum " ^ ename ^ " ")
    ++ d_attrlist () a
    ++ name
  | TSPtr (bt, a)  ->
    (* Parenthesize the ( * attr name) if a pointer to a function or an
        array. *)
    let (paren: doc option), (bt': typsig) =
      match bt with
      | TSFun _ | TSArray _ -> Some (text "("), bt
      | _ -> None, bt
    in
    let name' = text "*" ++ printAttributes a ++ name in
    let name'' = (* Put the parenthesis *)
      match paren with
        Some p -> p ++ name' ++ text ")"
      | _ -> name'
    in
    pretty_typsig_like_typ
      (Some name'')
      ()
      bt'

  | TSArray (elemt, lo, a) ->
    (* ignore the const attribute for arrays *)
    let a' = dropAttributes [ "pconst" ] a in
    let name' =
      if a' == [] then name else
      if nameOpt == None then printAttributes a' else
        text "(" ++ printAttributes a' ++ name ++ text ")"
    in
    pretty_typsig_like_typ
      (Some (name'
             ++ text "["
             ++ (match lo with None -> nil | Some e -> text (Z.to_string e))
             ++ text "]"))
      ()
      elemt

  | TSFun (restyp, args, isvararg, a) ->
    let name' =
      if a == [] then name else
      if nameOpt == None then printAttributes a else
        text "(" ++ printAttributes a ++ name ++ text ")"
    in
    pretty_typsig_like_typ
      (Some
         (name'
          ++ text "("
          ++ (align
              ++
              (if args = Some [] && isvararg then
                 text "..."
               else
                 (if args = None then nil
                  else if args = Some [] then text "void"
                  else
                    let pArg atype =
                      (pretty_typsig_like_typ None () atype)
                    in
                    (docList ~sep:(chr ',' ++ break) pArg) ()
                      (match args with None -> [] | Some args -> args))
                 ++ (if isvararg then break ++ text ", ..." else nil))
              ++ unalign)
          ++ text ")"))
      ()
      restyp

(** Pretty-print typsig like typ, because
    {!d_typsig} prints with CIL constructors. *)
let pretty_typsig_like_typ = pretty_typsig_like_typ None

(** HashSet of line numbers *)
let locs = Hashtbl.create 200

(** Visitor to count locs appearing inside a fundec. *)
class countFnVisitor = object
  inherit nopCilVisitor
  method! vstmt s =
    match s.skind with
    | Return (_, loc)
    | Goto (_, loc)
    | ComputedGoto (_, loc)
    | Break loc
    | Continue loc
    | If (_,_,_,loc,_)
    | Switch (_,_,_,loc,_)
    | Loop (_,loc,_,_,_)
      -> Hashtbl.replace locs loc.line (); DoChildren
    | _ ->
      DoChildren

  method! vinst = function
    | Set (_,_,loc,_)
    | Call (_,_,_,loc,_)
    | Asm (_,_,_,_,_,loc)
      -> Hashtbl.replace locs loc.line (); SkipChildren
    | _ -> SkipChildren

  method! vvdec _ = SkipChildren
  method! vexpr _ = SkipChildren
  method! vlval _ = SkipChildren
  method! vtype _ = SkipChildren
end

let fnvis = new countFnVisitor

(** Count the number of unique locations appearing in fundec [fn].
    Uses {!Cilfacade.locs} hashtable for intermediate computations
*)
let countLoc fn =
  let _ = visitCilFunction fnvis fn in
  let res = Hashtbl.length locs in
  Hashtbl.clear locs;
  res


let fundec_return_type f =
  match f.svar.vtype with
  | TFun (return_type, _, _, _) -> return_type
  | _ -> failwith "fundec_return_type: not TFun"


module StmtH = Hashtbl.Make (CilType.Stmt)

let stmt_fundecs: fundec StmtH.t ResettableLazy.t =
  ResettableLazy.from_fun (fun () ->
      let h = StmtH.create 113 in
      iterGlobals !current_file (function
          | GFun (fd, _) ->
            List.iter (fun stmt ->
                StmtH.replace h stmt fd
              ) fd.sallstmts
          | _ -> ()
        );
      h
    )


let get_pseudo_return_id fd =
  let start_id = 10_000_000_000 in (* TODO get max_sid? *)
  let sid = Hashtbl.hash fd.svar.vid in (* Need pure sid instead of Cil.new_sid for incremental, similar to vid in Cilfacade.create_var. We only add one return stmt per loop, so the hash from the functions vid should be unique. *)
  if sid < start_id then sid + start_id else sid

let pseudo_return_to_fun = StmtH.create 113

(** Find [fundec] which the [stmt] is in. *)
let find_stmt_fundec stmt =
  try StmtH.find pseudo_return_to_fun stmt
  with Not_found -> StmtH.find (ResettableLazy.force stmt_fundecs) stmt (* stmt argument must be explicit, otherwise force happens immediately *)


module VarinfoH = Hashtbl.Make (CilType.Varinfo)

let varinfo_fundecs: fundec VarinfoH.t ResettableLazy.t =
  ResettableLazy.from_fun (fun () ->
      let h = VarinfoH.create 111 in
      iterGlobals !current_file (function
          | GFun (fd, _) ->
            VarinfoH.replace h fd.svar fd
          | _ -> ()
        );
      h
    )

(** Find [fundec] by the function's [varinfo] (has the function name and type). *)
let find_varinfo_fundec vi = VarinfoH.find (ResettableLazy.force varinfo_fundecs) vi (* vi argument must be explicit, otherwise force happens immediately *)


module StringH = Hashtbl.Make (Printable.Strings)

let name_fundecs: fundec StringH.t ResettableLazy.t =
  ResettableLazy.from_fun (fun () ->
      let h = StringH.create 111 in
      iterGlobals !current_file (function
          | GFun (fd, _) ->
            StringH.replace h fd.svar.vname fd
          | _ -> ()
        );
      h
    )

(** Find [fundec] by the function's name. *)
(* TODO: why unused? *)
let find_name_fundec name = StringH.find (ResettableLazy.force name_fundecs) name (* name argument must be explicit, otherwise force happens immediately *)


type varinfo_role =
  | Formal of fundec
  | Local of fundec
  | Function
  | Global

let varinfo_roles: varinfo_role VarinfoH.t ResettableLazy.t =
  ResettableLazy.from_fun (fun () ->
      let h = VarinfoH.create 113 in
      iterGlobals !current_file (function
          | GFun (fd, _) ->
            VarinfoH.replace h fd.svar Function; (* function itself can be used as a variable (function pointer) *)
            List.iter (fun vi -> VarinfoH.replace h vi (Formal fd)) fd.sformals;
            List.iter (fun vi -> VarinfoH.replace h vi (Local fd)) fd.slocals
          | GVarDecl (vi, _) when Cil.isFunctionType vi.vtype ->
            VarinfoH.replace h vi Function
          | GVar (vi, _, _)
          | GVarDecl (vi, _) ->
            VarinfoH.replace h vi Global
          | _ -> ()
        );
      h
    )

(** Find the role of the [varinfo]. *)
let find_varinfo_role vi = VarinfoH.find (ResettableLazy.force varinfo_roles) vi (* vi argument must be explicit, otherwise force happens immediately *)

let is_varinfo_formal vi =
  match find_varinfo_role vi with
  | Formal _ -> true
  | exception Not_found
  | _ -> false


(** Find the scope of the [varinfo].
    If [varinfo] is a local or a formal argument of [fundec], then returns [Some fundec].
    If [varinfo] is a global or a function itself, then returns [None]. *)
let find_scope_fundec vi =
  match find_varinfo_role vi with
  | Formal fd
  | Local fd ->
    Some fd
  | Function
  | Global
  | exception Not_found ->
    None


let original_names: string VarinfoH.t ResettableLazy.t =
  (* only invert environment map when necessary (e.g. witnesses) *)
  ResettableLazy.from_fun (fun () ->
      let h = VarinfoH.create 113 in
      Hashtbl.iter (fun original_name (envdata, _) ->
          match envdata with
          | Cabs2cil.EnvVar vi when vi.vname <> "" -> (* TODO: fix temporary variables with empty names being in here *)
            VarinfoH.replace h vi original_name
          | _ -> ()
        ) Cabs2cil.environment;
      h
    )

(** Find the original name (in input source code) of the [varinfo].
    If it was renamed by CIL, then returns the original name before renaming.
    If it wasn't renamed by CIL, then returns the same name.
    If it was inserted by CIL (or Goblint), then returns [None]. *)
let find_original_name vi = VarinfoH.find_opt (ResettableLazy.force original_names) vi (* vi argument must be explicit, otherwise force happens immediately *)

module IntH = Hashtbl.Make (struct type t = int [@@deriving eq, hash] end)

class stmtSidVisitor h = object
  inherit nopCilVisitor
  method! vstmt s =
    IntH.replace h s.sid s;
    DoChildren
end

let stmt_sids: stmt IntH.t ResettableLazy.t =
  ResettableLazy.from_fun (fun () ->
      let h = IntH.create 113 in
      let visitor = new stmtSidVisitor h in
      visitCilFileSameGlobals visitor !current_file;
      h
    )

let pseudo_return_stmt_sids: stmt IntH.t = IntH.create 13

(** Find [stmt] by its [sid].
    @raise Not_found *)
let find_stmt_sid sid =
  try IntH.find pseudo_return_stmt_sids sid
  with Not_found -> IntH.find (ResettableLazy.force stmt_sids) sid

module FunLocH = Hashtbl.Make(CilType.Fundec)
module LocSet = Hashtbl.Make(CilType.Location)

(** Contains the locations of the upjumping gotos and the respective functions
 * they are being called in. *)
let funs_with_upjumping_gotos: unit LocSet.t FunLocH.t = FunLocH.create 13

let reset_lazy ?(keepupjumpinggotos=false) () =
  StmtH.clear pseudo_return_to_fun;
  if not keepupjumpinggotos then FunLocH.clear funs_with_upjumping_gotos;
  ResettableLazy.reset stmt_fundecs;
  ResettableLazy.reset varinfo_fundecs;
  ResettableLazy.reset name_fundecs;
  ResettableLazy.reset varinfo_roles;
  ResettableLazy.reset original_names;
  ResettableLazy.reset stmt_sids


let stmt_pretty_short () x =
  match x.skind with
  | Instr (y::ys) -> dn_instr () y
  | If (exp,_,_,_,_) -> dn_exp () exp
  | _ -> dn_stmt () x

(** Given a [Cil.file], reorders its [globals], inserts function declarations before function definitions.
    This function may be used after a code transformation to ensure that the order of globals yields a compilable program. *)
let add_function_declarations (file: Cil.file): unit =
  let globals = file.globals in
  let functions, non_functions = List.partition (fun g -> match g with GFun _ -> true | _ -> false) globals in
  let upto_last_type, non_types = GobList.until_last_with (fun g -> match g with GType _ -> true | _ -> false) non_functions in
  let declaration_from_GFun f = match f with
    | GFun (f, _) when BatString.starts_with_stdlib ~prefix:"__builtin" f.svar.vname ->
      (* Builtin functions should not occur in asserts generated, so there is no need to add declarations for them.*)
      None
    | GFun (f, _) ->
      Some (GVarDecl (f.svar, locUnknown))
    | _ -> failwith "Expected GFun, but was something else."
  in
  let fun_decls = List.filter_map declaration_from_GFun functions in
  let globals = upto_last_type @ fun_decls @ non_types @ functions in
  file.globals <- globals


(** Special index expression for some unknown index.
    Weakly updates array in assignment.
    Used for [exp.fast_global_inits]. *)
let any_index_exp = CastE (TInt (ptrdiff_ikind (), []), mkString "any_index") (* TODO: move back to Offset *)
