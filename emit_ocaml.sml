(* ??? sean mclaughlin formatter *)

structure Emit :> sig
  val emit : SmlSyntax.toplevel_defn list -> unit
end = struct
  open Util
  infixr 0 >>
  open SmlSyntax

  fun foldlSuper first middle start l =
      let
        fun foldl' acc l =
            case l of
                [] => acc
              | x::xs => foldl' (middle (x, acc)) xs
      in
        case l of
            [] => start
          | x::xs => foldl' (first (x, start)) xs
      end

  datatype indent
    = None
    | Incr
    | Decr

  datatype emittable
    = String of string
    | Newline of indent

  fun type_args_to_string args =
      case args of
          [] => ""
        | [arg] => arg ^ " "
        | _ => "(" ^ String.concatWith ", " args ^ ") "

  fun precedence TYPE =
      case TYPE of
          (TypeVar _ | ModProjType _ | ProdType [] | ProdType [_]) => 0
        | AppType _ => 1
        | ProdType _ => 2
        | ArrowType _ => 3

  fun emit_type TYPE acc =
      case TYPE of
          TypeVar name => String name :: acc
        | ArrowType (TYPE1, TYPE2) =>
          if precedence TYPE1 > 2
          then
            emit_type TYPE2
              (String ") -> " :: emit_type TYPE1 (String "(" :: acc))
          else
            emit_type TYPE2 (String " -> " :: emit_type TYPE1 acc)
        | ProdType TYPES =>
          (case TYPES of
               [] => String "unit" :: acc
             | _ =>
               foldlSuper
                 (fn (TYPE, acc) =>
                     if precedence TYPE > 1
                     then String ")" :: emit_type TYPE (String "(" :: acc)
                     else emit_type TYPE acc)
                 (fn (TYPE, acc) =>
                     if precedence TYPE > 1
                     then String ")" :: emit_type TYPE (String " * (" :: acc)
                     else emit_type TYPE (String " * " :: acc))
                 acc TYPES)
        | AppType (args, func) =>
          let
            fun emit_args args acc =
                case args of
                    [] => acc
                  | [arg] =>
                    if precedence arg > 0
                    then String ") " :: emit_type arg (String "(" :: acc)
                    else String " " :: emit_type arg acc
                  | arg::args =>
                    String ") "
                    :: List.foldl
                         (fn (arg, acc) => emit_type arg (String ", " :: acc))
                         (emit_type arg (String "(" :: acc))
                         args
          in
            emit_type func (emit_args args acc)
          end
        | ModProjType (STRUCT, field) =>
          String ("." ^ field) :: emit_struct STRUCT acc

  and emit_datatype mutual name args branches acc =
      Newline Decr
      :: foldlSuper
           (fn ((cons_name, type_opt), acc) =>
               case type_opt of
                   NONE => String cons_name :: acc
                 | SOME TYPE =>
                   String ")" :: emit_type TYPE (String (cons_name ^ " of (") :: acc))
           (fn ((cons_name, type_opt), acc) =>
               case type_opt of
                   NONE => String ("| " ^ cons_name) :: Newline None :: acc
                 | SOME TYPE =>
                   String ")"
                   :: emit_type TYPE
                        (String ("| " ^ cons_name ^ " of (") :: Newline None :: acc))
           (String "= "
            :: Newline Incr
            :: String
                 ((if mutual then "and " else "type ")
                  ^ type_args_to_string args
                  ^ name)
            :: acc)
           branches

  and emit_decl d acc =
      case d of
          BlankDecl => Newline None :: acc
        | StructureDecl (name, SIG) =>
          emit_sig SIG (String ("module " ^ name ^ " : ") :: acc)
        | TypeDecls {datatypes, aliases} =>
          foldlSuper
            (fn ((name, args, type_opt), acc) =>
                (case type_opt of
                     NONE =>
                     String ("type " ^ type_args_to_string args ^ name)
                     :: acc
                   | SOME TYPE =>
                     emit_type TYPE
                               (String
                                  ("type "
                                   ^ type_args_to_string args
                                   ^ name
                                   ^ " = ")
                                :: acc)))
            (fn ((name, args, type_opt), acc) =>
                (case type_opt of
                     NONE =>
                     String ("type "
                             ^ type_args_to_string args
                             ^ name)
                     :: acc
                   | SOME TYPE =>
                     emit_type TYPE
                               (String
                                  ("type "
                                   ^ type_args_to_string args
                                   ^ name
                                   ^ " = ")
                                :: acc)))
            (foldlSuper
               (fn ((name, args, branches), acc) =>
                   emit_datatype false name args branches acc)
               (fn ((name, args, branches), acc) =>
                   emit_datatype true name args branches acc)
               acc datatypes)
            aliases
        | ValDecl (name, TYPE) =>
          emit_type TYPE (String ("val " ^ name ^ " : ") :: acc)
        | SharingDecl (TYPE1, TYPE2) =>
          emit_type TYPE2
            (String " = " :: emit_type TYPE1 (String "sharing type " :: acc))

  and emit_sig SIG acc =
      case SIG of
          SigVar sig_name =>
          String sig_name :: acc
        | SigBody decls =>
          String "end"
          :: Newline Decr
          :: foldlSuper
               (fn (decl, acc) => emit_decl decl acc)
               (fn (decl, acc) => emit_decl decl (Newline None :: acc))
               (Newline Incr :: String "sig" :: acc)
               decls
        | WhereType (SIG, TYPE1, TYPE2) =>
          emit_type TYPE2
            (String " = "
             :: emit_type TYPE1
                  (String " with type " :: emit_sig SIG acc))

  and emit_pat PAT acc =
      case PAT of
          Wild => String "_" :: acc
        | VarPat name => String name :: acc
        | TuplePat pats =>
          (case pats of
               [] => String "()" :: acc
             | [PAT] => emit_pat PAT acc
             | pats =>
               String ")"
               :: foldlSuper
                    (fn (PAT, acc) => emit_pat PAT acc)
                    (fn (PAT, acc) => emit_pat PAT (String ", " :: acc))
                    (String "(" :: acc)
                    pats)
        | ListPat pats =>
          String "]"
          :: foldlSuper
               (fn (PAT, acc) => emit_pat PAT acc)
               (fn (PAT, acc) => emit_pat PAT (String ", " :: acc))
               (String "[" :: acc)
               pats
        | InjPat (name, PAT') =>
          String ")" :: emit_pat PAT' (String ("(" ^ name ^ " ") :: acc)
        | AscribedPat (PAT, TYPE) =>
          String ")"
          :: emit_type TYPE (String " : " :: emit_pat PAT (String "(" :: acc))
        | ConsPat (PAT1, PAT2) =>
          String ")"
          :: emit_pat PAT2 (String " :: " :: emit_pat PAT1 (String "(" :: acc))

  and emit_exp EXP acc =
      case EXP of
          ExpVar name => String name :: acc
        | TupleExp exps =>
          (case exps of
               [] => String "()" :: acc
             | [EXP] => emit_exp EXP acc
             | exps =>
               String ")"
               :: foldlSuper
                    (fn (EXP, acc) => emit_exp EXP acc)
                    (fn (EXP, acc) => emit_exp EXP (String ", " :: acc))
                    (String "(" :: acc)
                    exps)
        | ListExp exps =>
          String "]"
          :: foldlSuper
               (fn (EXP, acc) => emit_exp EXP acc)
               (fn (EXP, acc) => emit_exp EXP (String "; " :: acc))
               (String "[" :: acc)
               exps
        | CaseExp (EXP, cases) =>
          Newline None
          :: String ")"
          :: emit_cases
               (String "  "
                :: Newline None
                :: String " with"
                :: emit_exp EXP (String "(match " :: acc))
               cases
        | SeqExp exps =>
          String ")"
          :: foldlSuper
               (fn (EXP, acc) => emit_exp EXP acc)
               (fn (EXP, acc) => emit_exp EXP (String " " :: acc))
               (String "(" :: acc) exps
        | IntExp i =>
          String
            (if i < 0
             then "(-" ^ Int.toString (~i) ^ ")"
             else Int.toString i)
          :: acc
        | StringExp str =>
          String ("\"" ^ str ^ "\"") :: acc
        | LetExp (defns, EXP) =>
          String ")"
          :: emit_exp EXP
               (emit_defns defns true
                  (Newline None :: String "(" :: acc))
        | LamExp cases =>
          String ")"
          :: emit_cases
               (String "(fun " :: acc)
               cases
        | IfExp (e, et, ef) =>
          String ")"
          :: emit_exp ef
               (String "else "
                :: Newline None
                :: emit_exp et
                     (String "then "
                      :: Newline None
                      :: emit_exp e (String "(if " :: acc)))
        | BoolAnd =>
          String "&&" :: acc

  and emit_cases acc cases =
      foldlSuper
        (fn ((PAT, EXP), acc) =>
            Newline Decr
            :: emit_exp EXP
                        (Newline Incr
                         :: String " ->"
                         :: emit_pat PAT acc))
        (fn ((PAT, EXP), acc) =>
            Newline Decr
            :: emit_exp EXP
                        (Newline Incr
                         :: String " ->"
                         :: emit_pat PAT (String "| " :: acc)))
        acc
        cases

  and emit_defn d is_let acc =
      case d of
          BlankDefn => Newline None :: acc
        | StructureDefn (name, sig_opt, STRUCT) =>
          (if is_let then [String " in "] else [])
          @ emit_structure_defn name sig_opt STRUCT acc
        | TypeDefns {datatypes, aliases} =>
          (if is_let then [String " in "] else [])
          @ foldlSuper
            (fn ((name, args, TYPE), acc) =>
                emit_type TYPE
                  (String
                     ((case datatypes of [] => "type " | _ => "and ")
                      ^ type_args_to_string args
                      ^ name
                      ^ " = ")
                   :: acc))
            (fn ((name, args, TYPE), acc) =>
                emit_type TYPE
                  (String
                     ("and "
                      ^ type_args_to_string args
                      ^ name
                      ^ " = ")
                   :: Newline None
                   :: acc))
              (foldlSuper
                 (fn ((name, args, branches), acc) =>
                     emit_datatype false name args branches acc)
                 (fn ((name, args, branches), acc) =>
                     emit_datatype true name args branches acc)
                 acc datatypes)
              aliases
        | ValDefn (PAT, EXP) =>
          (if is_let then [String " in "] else [])
          @ emit_exp EXP (String " = " :: emit_pat PAT (String "let " :: acc))
        | OpenDefn STRUCT =>
          (if is_let then [String " in "] else [])
          @ emit_struct STRUCT (String (if is_let then "let open" else "open ") :: acc)
        | DatatypeCopy (name, TYPE) =>
          emit_type TYPE (String ("datatype " ^ name ^ " = datatype ") :: acc)
        | FunDefns funs =>
          (if is_let then [String " in "] else [])
          @ let
            fun emit_args args acc =
                foldlSuper
                  (fn (PAT, acc) => emit_pat PAT acc)
                  (fn (PAT, acc) => emit_pat PAT (String " " :: acc))
                  acc args

            fun emit_fun mutual ((name, args, type_opt, EXP), acc) =
                Newline Decr
                :: emit_exp EXP
                     (Newline Incr
                      :: String " ="
                      :: (case type_opt of
                              NONE =>
                              emit_args
                                args
                                (String
                                   ((if mutual then "and " else "let rec ")
                                    ^ name
                                    ^ " ")
                                 :: acc)
                            | SOME TYPE =>
                              emit_type
                                TYPE
                                (String " : "
                                 :: emit_args
                                      args
                                      (String ("let rec " ^ name ^ " ")
                                       :: acc))))
          in foldlSuper (emit_fun false) (emit_fun true) acc funs
          end

  and emit_structure_defn name sig_opt STRUCT acc =
      case sig_opt of
          NONE =>
          emit_struct STRUCT (String ("module " ^ name ^ " = ") :: acc)
        | SOME SIG =>
          emit_struct STRUCT
            (String " = "
             :: emit_sig SIG
                  (String ("module " ^ name ^ " : ") :: acc))

  and emit_defns defns is_let acc =
      foldlSuper
        (fn (defn, acc) => emit_defn defn is_let acc)
        (fn (defn, acc) => emit_defn defn is_let (Newline None :: acc))
        acc
        defns

  and emit_struct STRUCT acc =
      let
        fun peel_names STRUCT =
            case STRUCT of
                StructVar struct_name => ([struct_name], NONE)
              | StructBody decls => ([], SOME decls)
              | StructApp (fname, STRUCT') =>
                let val (names, body_opt) = peel_names STRUCT'
                in (fname::names, body_opt)
                end

        val (names, body_opt) = peel_names STRUCT

        val end_text = String.concatWith ")" (List.map (fn _ => "") names)
      in
        case body_opt of
            NONE => String (String.concatWith " (" names ^ end_text) :: acc
          | SOME body =>
            String "end"
            :: Newline Decr
            :: emit_defns body false
                 (case names of
                      [] => Newline Incr :: String "struct" :: acc
                    | _ =>
                      Newline Incr
                      :: String (String.concatWith " (" names ^ " (struct")
                      :: acc)

      end

  fun emit_toplevel_defn tld acc =
      case tld of
          TLSignature (name, SIG) =>
          emit_sig SIG (String ("module type " ^ name ^ " = ") :: acc)
        | TLStructure (name, sig_opt, STRUCT) =>
          emit_structure_defn name sig_opt STRUCT acc
        | TLFunctor (name, args, sig_opt, STRUCT) =>
          let
            val start_text =
                "module " ^ name ^ " ("

            val with_arg =
                String ") "
                :: foldlSuper
                     (fn (decl, acc) => emit_decl decl acc)
                     (fn (decl, acc) => emit_decl decl (String " " :: acc))
                     (String start_text :: acc)
                     args
          in
            case sig_opt of
                NONE =>
                emit_struct STRUCT (String "= " :: with_arg)
              | SOME SIG =>
                emit_struct STRUCT
                  (String " = "
                   :: emit_sig SIG (String ": " :: with_arg))
          end

  fun peel_strings e acc =
      case e of
          String s :: e' => peel_strings e' (s :: acc)
        | _ => (acc, e)

  fun flatten e =
      case e of
          [] => ()
        | String s :: e' =>
          let val (ss, e'') = peel_strings e []
          in emit [String.concat (List.rev ss)] >> flatten e''
          end
        | Newline None :: Newline None :: Newline None :: e' =>
          flatten (Newline None :: Newline None :: e')
        | Newline None :: Newline None :: e' =>
          emit [""] >> flatten e'
        | Newline None :: e' =>
          flatten e'
        | Newline Incr :: e' =>
          incr () >> flatten e'
        | Newline Decr :: e' =>
          decr () >> flatten e'

  val emit = fn defns =>
      let
        val emittable =
            foldlSuper
              (fn (defn, acc) => emit_toplevel_defn defn acc)
              (fn (defn, acc) => emit_toplevel_defn defn (Newline None :: acc))
              []
              defns
      in
        emit
          ["open Core.Std",
           "module List = struct",
           "  let concat = List.concat",
           "  let unzip = List.unzip",
           "  let map f l = List.map ~f:f l",
           "  let foldr f e l = List.fold_right ~f:(fun x acc -> f (x, acc)) ~init:e l",
           "  let foldl f e l = List.fold_left ~f:(fun acc x -> f (x, acc)) ~init:e l",
           "  let all f e l = List.fold_left ~f:(fun acc x -> f (x, acc)) ~init:e l",
           "end",
           "let option_iter f (opt, state) =",
           "  match opt with",
           "  | None -> (None, state)",
           "  | Some x ->",
           "    let (x', state') = f (x, state) in",
           "    (Some x', state')",
           "module ListPair = List"]
        >> flatten (List.rev emittable)
      end
end
