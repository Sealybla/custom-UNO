open! Core 
open! Async

module Queued_request = struct
  type t = {
    player_name : string;
    action : Action.Client_to_server.t;
    enqueued_at : Time_ns.t;
  }
end

module Connection_state = struct
  type t = {
    mutable player_name : string option;
  }
end

module Client_connection = struct
  type t = {
    name : string;
    writer : Action.Server_to_client.t Pipe.Writer.t;
  }
end

type t = {
  mutable clients : Client_connection.t String.Table.t;
  mutable game_state : Game_state.t option;
  request_writer : Queued_request.t Pipe.Writer.t;
  tcp_server : (Socket.Address.Inet.t, int) Tcp.Server.t;
}

let request_queue_size_budget = 1024

(* global broadcast loop *)
let broadcast t event = 
  Hashtbl.iter t.clients ~f:(fun client -> 
    if not (Pipe.is_closed client.writer) then
      Pipe.write_without_pushback client.writer event)

(* engine action loop that pulls actions off the pipe *)
let start_engine_loop t request_reader =
  don't_wait_for (Pipe.iter_without_pushback request_reader ~f:(fun { Queued_request.player_name; action; enqueued_at = _ } -> 
    match t.game_state with 
    | None -> () 
    | Some current_state -> 
      (* --- TEMPORARY MOCK BLOCK START --- *)
        (* This pattern replaces Game_state.apply_action until it is finished*)
        let is_valid_placeholder = true in
        if not is_valid_placeholder then ()
        else (
          let next_state = current_state in
          t.game_state <- Some next_state;
          
          (* Hardcoded card and color payloads so the compiler avoids record field errors *)
          let mock_top_card = { 
            Card.color = Card.Color.Red; 
            effect = Card.Effect.One; 
            id = 999 
          } in
          
          broadcast t (Action.Server_to_client.Pile_updated {
            top_card = mock_top_card;
            current_color = Card.Color.Red;
          });
          
          broadcast t (Action.Server_to_client.Turn_changed { 
            current_player_name = player_name 
        }))))

let start ~port () = 
  let clients = String.Table.create () in 
  let request_reader, request_writer = Pipe.create () in 
  Pipe.set_size_budget request_writer request_queue_size_budget;

  let t = { clients; game_state = None; request_writer; tcp_server = Obj.magic (); } in
  start_engine_loop t request_reader;

  let implementations = Rpc.Implementations.create_exn ~implementations:[
    Rpc.Rpc.implement Rpc_protocol.join_lobby_rpc (fun state name -> 
      if String.is_empty (String.strip name) then
        return (Or_error.error_string "Invalid name") 
      else match state.Connection_state.player_name with 
      | Some _ -> return (Or_error.error_string "Already registered on this connection")
      | None -> 
        if Hashtbl.mem clients name then
          return (Or_error.error_string "Username already taken in this session")
        else (
          state.player_name <- Some name;
          broadcast t (Action.Server_to_client.Lobby_updated { players = Hashtbl.keys clients});
          return (Ok ())
        ));

    Rpc.Pipe_rpc.implement Rpc_protocol.game_stream_rpc (fun state () -> 
      match state.Connection_state.player_name with 
      | None -> return (Error (Error.of_string "Not logged into lobby yet"))
      | Some name ->
        let reader, writer = Pipe.create () in 
        let connection = { Client_connection.name; writer } in
        Hashtbl.set clients ~key:name ~data:connection;

        (*sync up current lobby status*)
        broadcast t (Action.Server_to_client.Lobby_updated { players = Hashtbl.keys clients}); 
        return (Ok reader)) ;
     
    Rpc.Rpc.implement Rpc_protocol.take_action_rpc (fun state action -> 
      match state.Connection_state.player_name with 
      | None -> return (Or_error.error_string "Unauthorized session execution")
      | Some player_name ->
        let queued = { Queued_request.player_name; action; enqueued_at = Time_ns.now() } in
        let%map () = Pipe.write_if_open request_writer queued in
        Ok ()) ;
  ]
  ~on_unknown_rpc:`Close_connection
  ~on_exception:Log_on_background_exn 
in

let%map tcp_server = Rpc.Connection.serve ~implementations ~initial_connection_state:(fun _addr _conn -> 
  let state = { Connection_state.player_name = None } in 
  
  don't_wait_for (
    let%bind () = Rpc.Connection.close_finished _conn in 
    match state.Connection_state.player_name with 
    | None -> Deferred.unit 
    | Some name -> 
      Hashtbl.remove clients name;
      broadcast t (Action.Server_to_client.Lobby_updated { players = Hashtbl.keys clients});
      Deferred.unit
  );
  state)
  ~where_to_listen:(Tcp.Where_to_listen.of_port port)
  ()
  in 
  { t with tcp_server}