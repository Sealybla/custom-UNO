open! Core

(* Optional player accounts for the web UI: logging in gives you a personal
   library of named rule "modes" (saved rule texts) that survives across
   games and devices. The store lives in one sexp file next to the server.
   Passwords are salted-MD5 - a speed bump appropriate for a card game, not
   protection for secrets that matter. *)

module Mode = struct
  type t =
    { name : string
    ; rules_text : string
    }
  [@@deriving sexp, compare, equal]
end

module Account = struct
  type t =
    { salt : string
    ; password_hash : string
    ; display_name : string (* the capitalization used at sign-up *)
    ; mutable modes : Mode.t list
    }
  [@@deriving sexp]
end

module Snapshot = struct
  (* the whole store as written to disk: username key -> account *)
  type t = (string * Account.t) list [@@deriving sexp]
end

type t =
  { accounts : Account.t String.Table.t (* keyed by lowercased username *)
  ; random : Random.State.t
  }

let create ?random_state () =
  { accounts = String.Table.create ()
  ; random =
      (match random_state with
       | Some rs -> rs
       | None -> Random.State.make_self_init ())
  }
;;

let snapshot t : Snapshot.t = Hashtbl.to_alist t.accounts

let of_snapshot ?random_state (snap : Snapshot.t) =
  let t = create ?random_state () in
  List.iter snap ~f:(fun (key, account) ->
    Hashtbl.set t.accounts ~key ~data:account);
  t
;;

let max_modes = 20
let max_mode_name_len = 40
let max_rules_text_len = 20_000
let hash ~salt ~password = Md5.to_hex (Md5.digest_string (salt ^ "\x00" ^ password))

let generate_salt t =
  String.init 16 ~f:(fun _ -> "0123456789abcdef".[Random.State.int t.random 16])
;;

let validate_username username =
  let name = String.strip username in
  if String.is_empty name
  then Or_error.error_string "Username cannot be empty"
  else if String.length name > 24
  then Or_error.error_string "Username too long (24 characters max)"
  else Ok name
;;

(* log in, creating the account on first sight of the username *)
let login t ~username ~password
  : ([ `Created | `Logged_in ] * string * Mode.t list) Or_error.t
  =
  let open Or_error.Let_syntax in
  let%bind display_name = validate_username username in
  let%bind () =
    if String.is_empty password
    then Or_error.error_string "Password cannot be empty"
    else Ok ()
  in
  let key = String.lowercase display_name in
  match Hashtbl.find t.accounts key with
  | Some account ->
    if String.equal account.password_hash (hash ~salt:account.salt ~password)
    then Ok (`Logged_in, account.display_name, account.modes)
    else Or_error.error_string "Wrong password for that username"
  | None ->
    let salt = generate_salt t in
    let account =
      { Account.salt
      ; password_hash = hash ~salt ~password
      ; display_name
      ; modes = []
      }
    in
    Hashtbl.set t.accounts ~key ~data:account;
    Ok (`Created, display_name, [])
;;

let find_account t ~username =
  match Hashtbl.find t.accounts (String.lowercase (String.strip username)) with
  | Some account -> Ok account
  | None -> Or_error.error_string "No such account"
;;

let modes t ~username =
  match find_account t ~username with
  | Ok account -> account.modes
  | Error _ -> []
;;

(* save the current rule text under a name; a same-named mode (case
   insensitive) is replaced in place *)
let save_mode t ~username ~mode_name ~rules_text : Mode.t list Or_error.t =
  let open Or_error.Let_syntax in
  let%bind account = find_account t ~username in
  let mode_name = String.strip mode_name in
  let%bind () =
    if String.is_empty mode_name
    then Or_error.error_string "Give the mode a name"
    else if String.length mode_name > max_mode_name_len
    then Or_error.errorf "Mode name too long (%d characters max)" max_mode_name_len
    else if String.length rules_text > max_rules_text_len
    then Or_error.error_string "Rule text too large to save"
    else Ok ()
  in
  let mode = { Mode.name = mode_name; rules_text } in
  let replacing =
    List.exists account.modes ~f:(fun m ->
      String.Caseless.equal m.name mode_name)
  in
  let%bind () =
    if (not replacing) && List.length account.modes >= max_modes
    then Or_error.errorf "Mode limit reached (%d)" max_modes
    else Ok ()
  in
  account.modes
  <- (if replacing
      then
        List.map account.modes ~f:(fun m ->
          if String.Caseless.equal m.name mode_name then mode else m)
      else account.modes @ [ mode ]);
  Ok account.modes
;;

let delete_mode t ~username ~mode_name : Mode.t list Or_error.t =
  let open Or_error.Let_syntax in
  let%bind account = find_account t ~username in
  let before = List.length account.modes in
  account.modes
  <- List.filter account.modes ~f:(fun m ->
       not (String.Caseless.equal m.name (String.strip mode_name)));
  if List.length account.modes = before
  then Or_error.errorf "No saved mode named \"%s\"" (String.strip mode_name)
  else Ok account.modes
;;
