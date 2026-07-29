open! Core
open! Async
open Custom_uno

(* Bridges browser HTTP requests onto the game's Async-RPC protocol.
   Browsers can't speak bin_prot over TCP, so each joined browser player
   gets a dedicated RPC connection held here, and game events are queued
   as JSON until the page's /api/poll loop drains them. *)

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
  }

let session_expiry = Time_ns.Span.of_sec 60.

(* a browser that stops polling counts as disconnected: closing its RPC
   connection triggers the game server's usual dropout handling *)
let create ~rpc_port =
  let t = { sessions = String.Table.create (); rpc_port } in
  Clock_ns.every (Time_ns.Span.of_sec 15.) (fun () ->
    let now = Time_ns.now () in
    Hashtbl.filter_inplace t.sessions ~f:(fun (session : Session.t) ->
      let alive =
        (not (Rpc.Connection.is_closed session.conn))
        && Time_ns.Span.( < ) (Time_ns.diff now session.last_poll) session_expiry
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
  | Lobby_updated { players } ->
    sprintf {|{"type":"lobby","players":%s}|} (jlist (List.map players ~f:jstr))
  | Game_started
      { your_hand; top_card; current_color; player_names; current_player_name } ->
    sprintf
      {|{"type":"game_started","hand":%s,"top_card":%s,"current_color":%s,"players":%s,"current_player":%s}|}
      (jlist (List.map your_hand ~f:card_json))
      (card_json top_card)
      (jstr (color_name current_color))
      (jlist (List.map player_names ~f:jstr))
      (jstr current_player_name)
  | Hand_updated { your_hand } ->
    sprintf {|{"type":"hand","hand":%s}|} (jlist (List.map your_hand ~f:card_json))
  | Pile_updated { top_card; current_color } ->
    sprintf
      {|{"type":"pile","top_card":%s,"current_color":%s}|}
      (card_json top_card)
      (jstr (color_name current_color))
  | Turn_changed { current_player_name } ->
    sprintf {|{"type":"turn","player":%s}|} (jstr current_player_name)
  | Hand_counts { counts } ->
    sprintf
      {|{"type":"hand_counts","counts":%s}|}
      (jlist (List.map counts ~f:(fun (name, n) -> sprintf "[%s,%d]" (jstr name) n)))
  | Game_over { winner_name } ->
    sprintf {|{"type":"game_over","winner":%s}|} (jstr winner_name)
  | Uno_called { player_name } ->
    sprintf {|{"type":"uno","player":%s}|} (jstr player_name)
  | Rules_updated { player_name; num_rules } ->
    sprintf
      {|{"type":"rules_updated","player":%s,"num_rules":%d}|}
      (jstr player_name)
      num_rules
  | Action_rejected { reason } ->
    sprintf {|{"type":"rejected","reason":%s}|} (jstr reason)
;;

let join t ~name =
  let fresh_join () =
    match%bind
      Rpc.Connection.client
        (Tcp.Where_to_connect.of_host_and_port { host = "127.0.0.1"; port = t.rpc_port })
    with
    | Error exn -> return (Or_error.of_exn exn)
    | Ok conn ->
      (match%bind Rpc.Rpc.dispatch Rpc_protocol.join_lobby_rpc conn name with
       | Error err | Ok (Error err) ->
         let%map () = Rpc.Connection.close conn in
         Error err
       | Ok (Ok ()) ->
         (match%bind Rpc.Pipe_rpc.dispatch Rpc_protocol.game_stream_rpc conn () with
          | Error err | Ok (Error err) ->
            let%map () = Rpc.Connection.close conn in
            Error err
          | Ok (Ok (reader, _metadata)) ->
            let session =
              { Session.conn; events = Queue.create (); last_poll = Time_ns.now () }
            in
            Hashtbl.set t.sessions ~key:name ~data:session;
            don't_wait_for
              (Pipe.iter_without_pushback reader ~f:(fun event ->
                 Queue.enqueue session.events (event_json event)));
            return (Ok ())))
  in
  match Hashtbl.find t.sessions name with
  | Some session when not (Rpc.Connection.is_closed session.conn) ->
    (* same name joining again, e.g. after a page reload: re-attach *)
    session.last_poll <- Time_ns.now ();
    return (Ok ())
  | Some _ | None ->
    Hashtbl.remove t.sessions name;
    fresh_join ()
;;

let with_session t ~name ~f =
  match Hashtbl.find t.sessions name with
  | None ->
    return
      (Or_error.error_string
         "Not in the lobby (session may have expired) - reload the page")
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

let take_action t ~name ~action =
  with_session t ~name ~f:(fun session ->
    rpc_result (Rpc.Rpc.dispatch Rpc_protocol.take_action_rpc session.conn action))
;;

let start_game t ~name =
  with_session t ~name ~f:(fun session ->
    rpc_result (Rpc.Rpc.dispatch Rpc_protocol.start_game_rpc session.conn ()))
;;

let submit_rules t ~name ~text =
  with_session t ~name ~f:(fun session ->
    rpc_result (Rpc.Rpc.dispatch Rpc_protocol.submit_rules_rpc session.conn text))
;;

let poll t ~name =
  with_session t ~name ~f:(fun session ->
    let events = Queue.to_list session.events in
    Queue.clear session.events;
    return (Ok events))
;;

(* fresh snapshot from the server; queued events predate it, so drop them *)
let get_state t ~name =
  with_session t ~name ~f:(fun session ->
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
let error_body err = sprintf {|{"ok":false,"error":%s}|} (jstr (Error.to_string_hum err))

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

let handle t ~body req =
  let uri = Cohttp.Request.uri req in
  let with_name f =
    match Uri.get_query_param uri "name" with
    | None | Some "" ->
      respond_json ~status:`Bad_request (error_body (Error.of_string "missing player name"))
    | Some name -> f name
  in
  match Uri.path uri with
  | "/api/join" -> with_name (fun name -> respond_result (join t ~name))
  | "/api/poll" ->
    with_name (fun name ->
      match%bind poll t ~name with
      | Error err -> respond_json (error_body err)
      | Ok events ->
        respond_json (sprintf {|{"ok":true,"events":%s}|} (jlist events)))
  | "/api/state" ->
    with_name (fun name ->
      match%bind get_state t ~name with
      | Error err -> respond_json (error_body err)
      | Ok events ->
        respond_json (sprintf {|{"ok":true,"events":%s}|} (jlist events)))
  | "/api/start" -> with_name (fun name -> respond_result (start_game t ~name))
  | "/api/draw" ->
    with_name (fun name ->
      respond_result (take_action t ~name ~action:Action.Client_to_server.Draw))
  | "/api/pass" ->
    with_name (fun name ->
      respond_result (take_action t ~name ~action:Action.Client_to_server.Pass))
  | "/api/play" ->
    with_name (fun name ->
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
             ~name
             ~action:(Action.Client_to_server.Play { card_id; declared_color })))
  | "/api/rules" ->
    with_name (fun name ->
      let%bind text = Cohttp_async.Body.to_string body in
      respond_result (submit_rules t ~name ~text))
  | _ -> Cohttp_async.Server.respond `Not_found
;;
