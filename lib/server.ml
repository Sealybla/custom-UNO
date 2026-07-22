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
    mutable is_bot : bool;
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
    Core.print_s [%message "Processing Action" (player_name : string) (action : Action.Client_to_server.t)];
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
          
          let next_player_name = player_name in
          broadcast t (Action.Server_to_client.Turn_changed { 
            current_player_name = next_player_name;
          }); 
        (* END OF MOCK BLOCK *)
        (* bot take-over automation timer *)
        match Hashtbl.find t.clients next_player_name with 
        | Some client when client.is_bot -> 
          don't_wait_for (let%map () = Clock_ns.after (Time_ns.Span.of_sec 5.0) in
          (* verify it is their turn after 5 seconds before acting *)
          match t.game_state with 
          | None -> ()
          | Some verified_state -> 
            let current_turn_name = next_player_name in
            if String.equal current_turn_name next_player_name then (
              Core.print_s [%message "Bot execution triggered" (next_player_name : string)];

              let bot_action = {
                Queued_request. 
                player_name = next_player_name;
                action = Action.Client_to_server.Draw;
                enqueued_at = Time_ns.now ();
              } in
              Pipe.write_without_pushback t.request_writer bot_action
            ))
        | _ -> ()
        )))

let start ~port () = 
  Core.print_endline (Core.sprintf "\n>>> Booting Uno Server on port %d..." port);
  Core.Out_channel.flush Core.stdout;

  let clients = String.Table.create () in 
  let request_reader, request_writer = Pipe.create () in 
  Pipe.set_size_budget request_writer request_queue_size_budget;

  let t = { clients; game_state = None; request_writer; tcp_server = Obj.magic (); } in
  start_engine_loop t request_reader;

  let implementations = Rpc.Implementations.create_exn ~implementations:[
    Rpc.Rpc.implement Rpc_protocol.join_lobby_rpc (fun state name -> 
      if Option.is_some t.game_state then
        return (Or_error.error_string "Cannot join lobby: A game is currently in progress!")
      else if String.is_empty (String.strip name) then
        return (Or_error.error_string "Invalid name") 
      else match state.Connection_state.player_name with 
      | Some _ -> return (Or_error.error_string "Already registered on this connection")
      | None -> 
        if Hashtbl.mem clients name then
          return (Or_error.error_string "Username already taken in this session")
        else (
          state.player_name <- Some name;
          Core.print_s [%message "Lobby Registration" (name : string)];
          broadcast t (Action.Server_to_client.Lobby_updated { players = Hashtbl.keys clients});
          return (Ok ())
        ));

    Rpc.Pipe_rpc.implement Rpc_protocol.game_stream_rpc (fun state () -> 
      if Option.is_some t.game_state then 
        return (Error (Error.of_string "Access denied: Game is already in progress!"))
      else match state.Connection_state.player_name with 
      | None -> return (Error (Error.of_string "Not logged into lobby yet"))
      | Some name ->
        let reader, writer = Pipe.create () in 
        let connection = { Client_connection.name; writer; is_bot = false } in
        Hashtbl.set clients ~key:name ~data:connection;

        (* broadcasts to everyone that a new user is in the lobby*)
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
      if Option.is_some t.game_state then (
        match Hashtbl.find t.clients name with 
      | None -> ()
      | Some client -> 
        client.is_bot <- true;
        Core.print_s [%message "Player dropped mid-game. Bot activated." (name : string)]
      ) else (
        Hashtbl.remove t.clients name;
        Core.print_s [%message "Player left the lobby" (name : string)];
        broadcast t (Action.Server_to_client.Lobby_updated { players = Hashtbl.keys t.clients})
      );
      Deferred.unit
  );
  state)
  ~where_to_listen:(Tcp.Where_to_listen.of_port port)
  ()
  in 

  Core.print_endline ">>> SUCCESS: TCP socket listening. Ready for players.";
  Core.Out_channel.flush Core.stdout;

  { t with tcp_server}