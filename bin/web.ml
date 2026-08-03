open! Core
open! Async
open Custom_uno

(* Bridges browser HTTP requests onto the game's Async-RPC protocol. Browsers
   can't speak bin_prot over TCP, so each joined browser player gets a
   dedicated RPC connection held here, and game events are queued as JSON
   until the page's /api/poll loop drains them. *)

module Session = struct
  type t =
    { conn : Rpc.Connection.t
    ; events : string Queue.t (* JSON-encoded, in arrival order *)
    ; mutable last_poll : Time_ns.t
    }
end

type t =
  { sessions : Session.t String.Table.t
  ; rpc_port : int
  ; accounts : Accounts.t
  ; users_file : string
  ; tokens : string String.Table.t (* login token -> display name *)
  ; token_random : Random.State.t
  }

let session_expiry = Time_ns.Span.of_sec 8.

(* accounts live in one sexp file; missing means a fresh store, but a file
   that exists and cannot be parsed is fatal - dying at boot beats silently
   clobbering everyone's saved modes on the next write *)
let load_accounts users_file =
  match%bind Sys.file_exists users_file with
  | `No -> return (Accounts.create ())
  | `Yes | `Unknown ->
    (match%map
       Monitor.try_with (fun () ->
         Reader.load_sexp_exn users_file Accounts.Snapshot.t_of_sexp)
     with
     | Ok snap -> Accounts.of_snapshot snap
     | Error exn ->
       Core.eprintf
         ">>> Cannot read users file '%s': %s\n"
         users_file
         (Exn.to_string (Monitor.extract_exn exn));
       Core.exit 1)
;;

let save_accounts t =
  don't_wait_for
    (match%map
       Monitor.try_with (fun () ->
         Writer.save_sexp
           t.users_file
           (Accounts.Snapshot.sexp_of_t (Accounts.snapshot t.accounts)))
     with
     | Ok () -> ()
     | Error exn ->
       Core.eprintf
         "!! Failed to save users file '%s': %s\n"
         t.users_file
         (Exn.to_string (Monitor.extract_exn exn)))
;;

(* a browser that stops polling counts as disconnected: closing its RPC
   connection triggers the game server's usual dropout handling *)
let create ~rpc_port ~users_file =
  let%map accounts = load_accounts users_file in
  let t =
    { sessions = String.Table.create ()
    ; rpc_port
    ; accounts
    ; users_file
    ; tokens = String.Table.create ()
    ; token_random = Random.State.make_self_init ()
    }
  in
  Clock_ns.every (Time_ns.Span.of_sec 3.) (fun () ->
    let now = Time_ns.now () in
    Hashtbl.filter_inplace t.sessions ~f:(fun (session : Session.t) ->
      let alive =
        (not (Rpc.Connection.is_closed session.conn))
        && Time_ns.Span.( < )
             (Time_ns.diff now session.last_poll)
             session_expiry
      in
      if not alive then don't_wait_for (Rpc.Connection.close session.conn);
      alive));
  t
;;

let json_escape s =
  String.concat_map s ~f:(fun c ->
    match c with
    | '"' -> {|\"|}
    | '\\' -> {|\\|}
    | '\n' -> {|\n|}
    | '\r' -> {|\r|}
    | '\t' -> {|\t|}
    | c when Char.to_int c < 32 -> sprintf {|\u%04x|} (Char.to_int c)
    | c -> String.of_char c)
;;

let jstr s = "\"" ^ json_escape s ^ "\""
let jlist items = "[" ^ String.concat items ~sep:"," ^ "]"
let color_name color = Sexp.to_string ([%sexp_of: Card.Color.t] color)

let card_json (card : Card.t) =
  sprintf
    {|{"id":%d,"color":%s,"value":%s}|}
    card.id
    (jstr (color_name card.color))
    (jstr (Sexp.to_string ([%sexp_of: Card.Value.t] card.value)))
;;

let event_json (event : Action.Server_to_client.t) =
  match event with
  | Lobby_updated { players; ready_players; last_winner } ->
    sprintf
      {|{"type":"lobby","players":%s,"ready":%s,"last_winner":%s}|}
      (jlist (List.map players ~f:jstr))
      (jlist (List.map ready_players ~f:jstr))
      (match last_winner with Some w -> jstr w | None -> "null")
  | Game_started
      { your_hand
      ; top_card
      ; current_color
      ; player_names
      ; current_player_name
      ; pending_draws
      ; stacking_enabled
      } ->
    sprintf
      {|{"type":"game_started","hand":%s,"top_card":%s,"current_color":%s,"players":%s,"current_player":%s,"pending":%d,"stacking":%b}|}
      (jlist (List.map your_hand ~f:card_json))
      (card_json top_card)
      (jstr (color_name current_color))
      (jlist (List.map player_names ~f:jstr))
      (jstr current_player_name)
      pending_draws
      stacking_enabled
  | Hand_updated { your_hand; playable_ids } ->
    sprintf
      {|{"type":"hand","hand":%s,"playable":%s}|}
      (jlist (List.map your_hand ~f:card_json))
      (jlist (List.map playable_ids ~f:Int.to_string))
  | Pile_updated { top_card; current_color; pending_draws } ->
    sprintf
      {|{"type":"pile","top_card":%s,"current_color":%s,"pending":%d}|}
      (card_json top_card)
      (jstr (color_name current_color))
      pending_draws
  | Turn_changed { current_player_name; can_pass; stack_value } ->
    sprintf
      {|{"type":"turn","player":%s,"can_pass":%b,"stack_value":%s}|}
      (jstr current_player_name)
      can_pass
      (match stack_value with
       | Some v -> jstr (Sexp.to_string ([%sexp_of: Card.Value.t] v))
       | None -> "null")
  | Hand_counts { counts } ->
    sprintf
      {|{"type":"hand_counts","counts":%s}|}
      (jlist
         (List.map counts ~f:(fun (name, n) ->
            sprintf "[%s,%d]" (jstr name) n)))
  | Game_over { winner_name } ->
    sprintf {|{"type":"game_over","winner":%s}|} (jstr winner_name)
  | Uno_called { player_name } ->
    sprintf {|{"type":"uno","player":%s}|} (jstr player_name)
  | Uno_penalty { player_name; count; caught } ->
    sprintf
      {|{"type":"uno_penalty","player":%s,"count":%d,"caught":%b}|}
      (jstr player_name)
      count
      caught
  | Turn_countdown { player_name; seconds } ->
    sprintf
      {|{"type":"countdown","player":%s,"seconds":%d}|}
      (jstr player_name)
      seconds
  | Rules_updated { player_name; num_rules; rules_text } ->
    sprintf
      {|{"type":"rules_updated","player":%s,"num_rules":%d,"rules_text":%s}|}
      (jstr player_name)
      num_rules
      (jstr rules_text)
  | Action_rejected { reason } ->
    sprintf {|{"type":"rejected","reason":%s}|} (jstr reason)
  | Player_skipped { player_name } ->
    sprintf {|{"type":"skipped","player":%s}|} (jstr player_name)
  | Forced_draw { player_name; count } ->
    sprintf
      {|{"type":"forced_draw","player":%s,"count":%d}|}
      (jstr player_name)
      count
  | Direction_changed { direction } ->
    sprintf
      {|{"type":"direction","clockwise":%b}|}
      (match direction with Clockwise -> true | Counter -> false)
;;

(* names are only unique within a room, so sessions key on both *)
let session_key ~code ~name = code ^ "/" ^ name

let connect t =
  Rpc.Connection.client
    (Tcp.Where_to_connect.of_host_and_port { host = "127.0.0.1"; port = t.rpc_port })
;;

let create_room t =
  match%bind connect t with
  | Error exn -> return (Or_error.of_exn exn)
  | Ok conn ->
    let%bind result = Rpc.Rpc.dispatch Rpc_protocol.create_room_rpc conn () in
    let%map () = Rpc.Connection.close conn in
    (match result with
     | Error err | Ok (Error err) -> Error err
     | Ok (Ok code) -> Ok code)
;;

let join t ~code ~name =
  let key = session_key ~code ~name in
  let fresh_join () =
    match%bind connect t with
    | Error exn -> return (Or_error.of_exn exn)
    | Ok conn ->
      (match%bind
         Rpc.Rpc.dispatch
           Rpc_protocol.join_lobby_rpc
           conn
           { Rpc_protocol.Join_query.code; player_name = name }
       with
       | Error err | Ok (Error err) ->
         let%map () = Rpc.Connection.close conn in
         Error err
       | Ok (Ok ()) ->
         (match%bind
            Rpc.Pipe_rpc.dispatch Rpc_protocol.game_stream_rpc conn ()
          with
          | Error err | Ok (Error err) ->
            let%map () = Rpc.Connection.close conn in
            Error err
          | Ok (Ok (reader, _metadata)) ->
            let session =
              { Session.conn
              ; events = Queue.create ()
              ; last_poll = Time_ns.now ()
              }
            in
            Hashtbl.set t.sessions ~key ~data:session;
            don't_wait_for
              (Pipe.iter_without_pushback reader ~f:(fun event ->
                 Queue.enqueue session.events (event_json event)));
            return (Ok ())))
  in
  match Hashtbl.find t.sessions key with
  | Some session when not (Rpc.Connection.is_closed session.conn) ->
    (* same player joining again, e.g. after a page reload: re-attach *)
    session.last_poll <- Time_ns.now ();
    return (Ok ())
  | Some _ | None ->
    Hashtbl.remove t.sessions key;
    fresh_join ()
;;

let with_session t ~code ~name ~f =
  match Hashtbl.find t.sessions (session_key ~code ~name) with
  | None ->
    return
      (Or_error.error_string
         "Not in the room (session may have expired) - reload the page")
  | Some session ->
    session.last_poll <- Time_ns.now ();
    f session
;;

(* flatten the rpc-transport error and the game's own error into one *)
let rpc_result deferred =
  match%map deferred with
  | Error err | Ok (Error err) -> Error err
  | Ok (Ok ()) -> Ok ()
;;

(* an explicit "leaving" signal from the page's unload beacon: drop the session
   and close its RPC connection right away so the game server converts the
   player to a bot immediately, instead of waiting out the poll-silence
   timeout. Always Ok — a beacon fires with no one listening for the reply. *)
let leave t ~code ~name =
  let key = session_key ~code ~name in
  (match Hashtbl.find t.sessions key with
   | None -> ()
   | Some session ->
     Hashtbl.remove t.sessions key;
     don't_wait_for (Rpc.Connection.close session.conn));
  return (Ok ())
;;

let take_action t ~code ~name ~action =
  with_session t ~code ~name ~f:(fun session ->
    rpc_result (Rpc.Rpc.dispatch Rpc_protocol.take_action_rpc session.conn action))
;;

let start_game t ~code ~name =
  with_session t ~code ~name ~f:(fun session ->
    rpc_result (Rpc.Rpc.dispatch Rpc_protocol.start_game_rpc session.conn ()))
;;

let submit_rules t ~code ~name ~text =
  with_session t ~code ~name ~f:(fun session ->
    rpc_result (Rpc.Rpc.dispatch Rpc_protocol.submit_rules_rpc session.conn text))
;;

let set_ready t ~code ~name ~is_ready =
  with_session t ~code ~name ~f:(fun session ->
    rpc_result (Rpc.Rpc.dispatch Rpc_protocol.set_ready_rpc session.conn is_ready))
;;

let poll t ~code ~name =
  with_session t ~code ~name ~f:(fun session ->
    let events = Queue.to_list session.events in
    Queue.clear session.events;
    return (Ok events))
;;

(* fresh snapshot from the server; queued events predate it, so drop them *)
let get_state t ~code ~name =
  with_session t ~code ~name ~f:(fun session ->
    Queue.clear session.events;
    match%map Rpc.Rpc.dispatch Rpc_protocol.get_state_rpc session.conn () with
    | Error err | Ok (Error err) -> Error err
    | Ok (Ok events) -> Ok (List.map events ~f:event_json))
;;

let json_headers = Cohttp.Header.of_list [ "Content-Type", "application/json" ]

let respond_json ?(status = `OK) body =
  Cohttp_async.Server.respond_string ~headers:json_headers ~status body
;;

let ok_body = {|{"ok":true}|}

let error_body err =
  sprintf {|{"ok":false,"error":%s}|} (jstr (Error.to_string_hum err))
;;

let respond_result result =
  match%bind result with
  | Ok () -> respond_json ok_body
  | Error err -> respond_json (error_body err)
;;

let color_of_string = function
  | "red" -> Some Card.Color.Red
  | "green" -> Some Card.Color.Green
  | "blue" -> Some Card.Color.Blue
  | "yellow" -> Some Card.Color.Yellow
  | _ -> None
;;

(* ---------- optional accounts: login + saved rule modes ---------- *)

let generate_token t =
  String.init 32 ~f:(fun _ ->
    "0123456789abcdef".[Random.State.int t.token_random 16])
;;

let modes_json modes =
  jlist
    (List.map modes ~f:(fun (m : Accounts.Mode.t) ->
       sprintf {|{"name":%s,"text":%s}|} (jstr m.name) (jstr m.rules_text)))
;;

let account_json ?created ~user ~token ~modes () =
  sprintf
    {|{"ok":true%s,"user":%s,"token":%s,"modes":%s}|}
    (match created with
     | None -> ""
     | Some c -> sprintf {|,"created":%b|} c)
    (jstr user)
    (jstr token)
    (modes_json modes)
;;

let with_token t uri ~f =
  match
    Option.bind (Uri.get_query_param uri "token") ~f:(Hashtbl.find t.tokens)
  with
  | Some username -> f username
  | None ->
    respond_json
      (error_body
         (Error.of_string "Not logged in (or the server restarted) - log in again"))
;;

let handle t ~body req =
  let uri = Cohttp.Request.uri req in
  let with_ident f =
    match Uri.get_query_param uri "code", Uri.get_query_param uri "name" with
    | Some code, Some name
      when (not (String.is_empty code)) && not (String.is_empty name) ->
      f ~code:(String.uppercase (String.strip code)) ~name
    | _ ->
      respond_json
        ~status:`Bad_request
        (error_body (Error.of_string "missing room code or player name"))
  in
  match Uri.path uri with
  | "/api/check-rules" ->
    (* parse-only dry run for live editor feedback; no session needed *)
    let%bind text = Cohttp_async.Body.to_string body in
    (match Rule_parser.parse_ruleset_checked text with
     | Ok (rules, warnings) ->
       let warning_json (w : Rule_parser.Lint.t) =
         sprintf
           {|{"rule":%s,"kind":%s,"message":%s,"fix":%s}|}
           (jstr w.rule_name)
           (jstr
              (match w.kind with
               | Missing_play -> "missing_play"
               | Missing_advance -> "missing_advance"
               | Missing_set_color -> "missing_set_color"
               | Missing_turn -> "missing_turn"
               | Dead_rule -> "dead_rule"))
           (jstr w.message)
           (match w.fix with
            | Some f -> jstr f
            | None -> "null")
       in
       respond_json
         (sprintf
            {|{"ok":true,"num_rules":%d,"warnings":%s}|}
            (List.length rules)
            (jlist (List.map warnings ~f:warning_json)))
     | Error err -> respond_json (error_body err))
  | "/api/preset-rules" ->
    (* the expanded rule text behind a preset, so the editor can offer its
       rules for copy-and-customize *)
    (match Option.bind (Uri.get_query_param uri "name") ~f:Presets.find with
     | None ->
       respond_json
         ~status:`Bad_request
         (error_body (Error.of_string "unknown preset"))
     | Some text -> respond_json (sprintf {|{"ok":true,"text":%s}|} (jstr text)))
  | "/api/create-room" ->
    (match%bind create_room t with
     | Error err -> respond_json (error_body err)
     | Ok code -> respond_json (sprintf {|{"ok":true,"code":%s}|} (jstr code)))
  | "/api/join" -> with_ident (fun ~code ~name -> respond_result (join t ~code ~name))
  | "/api/leave" -> with_ident (fun ~code ~name -> respond_result (leave t ~code ~name))
  | "/api/poll" ->
    with_ident (fun ~code ~name ->
      match%bind poll t ~code ~name with
      | Error err -> respond_json (error_body err)
      | Ok events ->
        respond_json (sprintf {|{"ok":true,"events":%s}|} (jlist events)))
  | "/api/state" ->
    with_ident (fun ~code ~name ->
      match%bind get_state t ~code ~name with
      | Error err -> respond_json (error_body err)
      | Ok events ->
        respond_json (sprintf {|{"ok":true,"events":%s}|} (jlist events)))
  | "/api/start" ->
    with_ident (fun ~code ~name -> respond_result (start_game t ~code ~name))
  | "/api/ready" ->
    with_ident (fun ~code ~name ->
      let is_ready =
        match Uri.get_query_param uri "on" with
        | Some "false" -> false
        | _ -> true
      in
      respond_result (set_ready t ~code ~name ~is_ready))
  | "/api/draw" ->
    with_ident (fun ~code ~name ->
      respond_result (take_action t ~code ~name ~action:Action.Client_to_server.Draw))
  | "/api/pass" ->
    with_ident (fun ~code ~name ->
      respond_result (take_action t ~code ~name ~action:Action.Client_to_server.Pass))
  | "/api/uno" ->
    with_ident (fun ~code ~name ->
      respond_result
        (take_action t ~code ~name ~action:Action.Client_to_server.Call_uno))
  | "/api/play" ->
    with_ident (fun ~code ~name ->
      match Option.bind (Uri.get_query_param uri "card_id") ~f:Int.of_string_opt with
      | None ->
        respond_json
          ~status:`Bad_request
          (error_body (Error.of_string "missing or invalid card_id"))
      | Some card_id ->
        let declared_color =
          Option.bind (Uri.get_query_param uri "color") ~f:color_of_string
        in
        respond_result
          (take_action
             t
             ~code
             ~name
             ~action:
               (Action.Client_to_server.Play { card_id; declared_color })))
  | "/api/rules" ->
    with_ident (fun ~code ~name ->
      let%bind text = Cohttp_async.Body.to_string body in
      respond_result (submit_rules t ~code ~name ~text))
  | "/api/login" ->
    (* body is "username\npassword"; unknown usernames are signed up *)
    let%bind body = Cohttp_async.Body.to_string body in
    (match String.lsplit2 body ~on:'\n' with
     | None ->
       respond_json
         ~status:`Bad_request
         (error_body (Error.of_string "malformed login request"))
     | Some (username, password) ->
       (match Accounts.login t.accounts ~username ~password with
        | Error err -> respond_json (error_body err)
        | Ok (status, user, modes) ->
          save_accounts t;
          let token = generate_token t in
          Hashtbl.set t.tokens ~key:token ~data:user;
          let created = match status with `Created -> true | `Logged_in -> false in
          Core.print_s [%message "Login" (user : string) (created : bool)];
          respond_json (account_json ~created ~user ~token ~modes ())))
  | "/api/me" ->
    (* restore a remembered session after a page reload *)
    with_token t uri ~f:(fun user ->
      let token = Option.value (Uri.get_query_param uri "token") ~default:"" in
      let modes = Accounts.modes t.accounts ~username:user in
      respond_json (account_json ~user ~token ~modes ()))
  | "/api/mode-save" ->
    with_token t uri ~f:(fun user ->
      match Uri.get_query_param uri "mode" with
      | None ->
        respond_json
          ~status:`Bad_request
          (error_body (Error.of_string "missing mode name"))
      | Some mode_name ->
        let%bind rules_text = Cohttp_async.Body.to_string body in
        (match
           Accounts.save_mode t.accounts ~username:user ~mode_name ~rules_text
         with
         | Error err -> respond_json (error_body err)
         | Ok modes ->
           save_accounts t;
           respond_json (sprintf {|{"ok":true,"modes":%s}|} (modes_json modes))))
  | "/api/mode-delete" ->
    with_token t uri ~f:(fun user ->
      match Uri.get_query_param uri "mode" with
      | None ->
        respond_json
          ~status:`Bad_request
          (error_body (Error.of_string "missing mode name"))
      | Some mode_name ->
        (match Accounts.delete_mode t.accounts ~username:user ~mode_name with
         | Error err -> respond_json (error_body err)
         | Ok modes ->
           save_accounts t;
           respond_json (sprintf {|{"ok":true,"modes":%s}|} (modes_json modes))))
  | _ -> Cohttp_async.Server.respond `Not_found
;;
