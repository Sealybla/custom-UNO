open! Core
open! Async

module Queued_request = struct
  type t =
    { player_name : string
    ; action : Action.Client_to_server.t
    ; enqueued_at : Time_ns.t
    }
end

module Connection_state = struct
  type t = { mutable player_name : string option }
end

module Client_connection = struct
  type t =
    { name : string
    ; writer : Action.Server_to_client.t Pipe.Writer.t
    ; mutable is_bot : bool
    }
end

type t = {
  clients : Client_connection.t String.Table.t;
  mutable game_state : Game_state.t option;
  request_writer : Queued_request.t Pipe.Writer.t;
}

let request_queue_size_budget = 1024

(* global broadcast loop *)
let broadcast t event =
  Hashtbl.iter t.clients ~f:(fun client ->
    if not (Pipe.is_closed client.writer)
    then Pipe.write_without_pushback client.writer event)
;;

let player_id_of_name state name = 
  List.find_map state.Game_state.players ~f:(fun p -> 
    if String.equal (Player.get_name p) name then Some (Player.get_id p) else None)
;;

let name_of_player_id state id =
  match List.nth state.Game_state.players id with 
  | Some p -> Some (Player.get_name p)
  | None -> None 
;; 

let send_hands t state = 
  List.iter state.Game_state.players ~f:(fun player ->
    match Hashtbl.find t.clients (Player.get_name player) with 
    | None -> ()
    | Some client -> 
      let hand = List.filter_map (Player.get_hand player) ~f:(fun card_id ->
        Game_state.Card_registry.find state.Game_state.card_registry card_id
        |> Or_error.ok)
      in 
      if not (Pipe.is_closed client.writer) 
      then 
        Pipe.write_without_pushback client.writer (Action.Server_to_client.Hand_updated { your_hand = hand}))
;;

let maybe_schedule_bot t next_state current_player_name =
  match Hashtbl.find t.clients current_player_name with
  | Some client when client.is_bot ->
    let bot_turn = next_state.Game_state.turn in
    don't_wait_for
      (let%map () = Clock_ns.after (Time_ns.Span.of_sec 5.0) in
       match t.game_state with
       | None -> ()
       | Some verified_state ->
         if Int.equal verified_state.Game_state.turn bot_turn
            && Option.is_none verified_state.Game_state.winner
         then (
           Core.print_s
             [%message "Bot execution triggered" (current_player_name : string)];
           Pipe.write_without_pushback
             t.request_writer
             { Queued_request.player_name = current_player_name
             ; action = Action.Client_to_server.Draw
             ; enqueued_at = Time_ns.now ()
             }))
  | _ -> ()
;;

(* engine action loop that pulls actions off the pipe *)
let start_engine_loop t request_reader =
  don't_wait_for (Pipe.iter_without_pushback request_reader ~f:(fun { Queued_request.player_name; action; enqueued_at = _ } -> 
    Core.print_s [%message "Processing Action" (player_name : string) (action : Action.Client_to_server.t)];
    match t.game_state with 
    | None -> () 
    | Some current_state -> 
      (match player_id_of_name current_state player_name with 
      | None -> () 
      | Some player_id -> 
        (match Game_state.apply_action current_state ~player_id ~action with 
        | Error e -> Core.print_s [%message "Rejected action" (player_name : string) (e : Error.t)]
        | Ok next_state -> 
          t.game_state <- Some next_state; 
          broadcast t (Action.Server_to_client.Pile_updated 
          { top_card = next_state.top_card 
           ; current_color = next_state.current_color
          }); 
           send_hands t next_state;
           (match next_state.winner with 
           | Some winner_id -> 
            (match name_of_player_id next_state winner_id with 
            | Some winner_name -> 
              broadcast t (Action.Server_to_client.Game_over {winner_name}) 
            | None -> ()) 
          | None -> 
            (match name_of_player_id next_state next_state.turn with 
            | None -> ()
            | Some current_player_name ->
              broadcast t (Action.Server_to_client.Turn_changed { current_player_name }); 
              maybe_schedule_bot t next_state current_player_name))))))

let start ~port () = 
  Core.print_endline (Core.sprintf "\n>>> Booting Uno Server on port %d..." port);
  Core.Out_channel.flush Core.stdout;
  let clients = String.Table.create () in
  let request_reader, request_writer = Pipe.create () in
  Pipe.set_size_budget request_writer request_queue_size_budget;

  let t = { clients; game_state = None; request_writer;} in
  start_engine_loop t request_reader;
  let implementations =
    Rpc.Implementations.create_exn
      ~implementations:
        [ Rpc.Rpc.implement Rpc_protocol.join_lobby_rpc (fun state name ->
            if Option.is_some t.game_state
            then
              return
                (Or_error.error_string
                   "Cannot join lobby: A game is currently in progress!")
            else if String.is_empty (String.strip name)
            then return (Or_error.error_string "Invalid name")
            else (
              match state.Connection_state.player_name with
              | Some _ ->
                return
                  (Or_error.error_string
                     "Already registered on this connection")
              | None ->
                if Hashtbl.mem clients name
                then
                  return
                    (Or_error.error_string
                       "Username already taken in this session")
                else (
                  state.player_name <- Some name;
                  Core.print_s
                    [%message "Lobby Registration" (name : string)];
                  broadcast
                    t
                    (Action.Server_to_client.Lobby_updated
                       { players = Hashtbl.keys clients });
                  return (Ok ()))))
        ; Rpc.Pipe_rpc.implement
            Rpc_protocol.game_stream_rpc
            (fun state () ->
               if Option.is_some t.game_state
               then
                 return
                   (Error
                      (Error.of_string
                         "Access denied: Game is already in progress!"))
               else (
                 match state.Connection_state.player_name with
                 | None ->
                   return
                     (Error (Error.of_string "Not logged into lobby yet"))
                 | Some name ->
                   let reader, writer = Pipe.create () in
                   let connection =
                     { Client_connection.name; writer; is_bot = false }
                   in
                   Hashtbl.set clients ~key:name ~data:connection;
                   (* broadcasts to everyone that a new user is in the lobby *)
                   broadcast
                     t
                     (Action.Server_to_client.Lobby_updated
                        { players = Hashtbl.keys clients });
                   return (Ok reader)))
        ; Rpc.Rpc.implement Rpc_protocol.take_action_rpc (fun state action ->
            match state.Connection_state.player_name with
            | None ->
              return (Or_error.error_string "Unauthorized session execution")
            | Some player_name ->
              let queued =
                { Queued_request.player_name
                ; action
                ; enqueued_at = Time_ns.now ()
                }
              in
              let%map () = Pipe.write_if_open request_writer queued in
              Ok ())
        ]
      ~on_unknown_rpc:`Close_connection
      ~on_exception:Log_on_background_exn
  in
  let%map tcp_server =
    Rpc.Connection.serve
      ~implementations
      ~initial_connection_state:(fun _addr _conn ->
        let state = { Connection_state.player_name = None } in
        don't_wait_for
          (let%bind () = Rpc.Connection.close_finished _conn in
           match state.Connection_state.player_name with
           | None -> Deferred.unit
           | Some name ->
             if Option.is_some t.game_state
             then (
               match Hashtbl.find t.clients name with
               | None -> ()
               | Some client ->
                 client.is_bot <- true;
                 Core.print_s
                   [%message
                     "Player dropped mid-game. Bot activated."
                       (name : string)])
             else (
               Hashtbl.remove t.clients name;
               Core.print_s
                 [%message "Player left the lobby" (name : string)];
               broadcast
                 t
                 (Action.Server_to_client.Lobby_updated
                    { players = Hashtbl.keys t.clients }));
             Deferred.unit);
        state)
      ~where_to_listen:(Tcp.Where_to_listen.of_port port)
      ()
  in
  Core.print_endline ">>> SUCCESS: TCP socket listening. Ready for players.";
  Core.Out_channel.flush Core.stdout;
  tcp_server
