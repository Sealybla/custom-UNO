open! Core
open! Async

module Queued_request = struct
  type t =
    { player_name : string
    ; action : Action.Client_to_server.t
    ; enqueued_at : Time_ns.t
    }
end

module Client_connection = struct
  type t =
    { name : string
    ; writer : Action.Server_to_client.t Pipe.Writer.t
    ; mutable is_bot : bool
    }
end

(* an isolated lobby/game: its own players, ruleset, and engine loop *)
module Room = struct
  type t =
    { code : string
    ; clients : Client_connection.t String.Table.t
    ; mutable game_state : Game_state.t option
    ; mutable ruleset : Rule_engine.Ruleset.t
    ; request_writer : Queued_request.t Pipe.Writer.t
    }
end

module Connection_state = struct
  type t =
    { mutable player_name : string option
    ; mutable room : Room.t option
    }
end

type t =
  { rooms : Room.t String.Table.t
  ; default_ruleset : Rule_engine.Ruleset.t
  ; random : Random.State.t
  }

let request_queue_size_budget = 1024

(* room-wide broadcast *)
let broadcast (room : Room.t) event =
  Hashtbl.iter room.clients ~f:(fun client ->
    if not (Pipe.is_closed client.writer)
    then Pipe.write_without_pushback client.writer event)
;;

let player_id_of_name state name =
  List.find_map state.Game_state.players ~f:(fun p ->
    if String.equal (Player.get_name p) name
    then Some (Player.get_id p)
    else None)
;;

let name_of_player_id state id =
  match List.nth state.Game_state.players id with
  | Some p -> Some (Player.get_name p)
  | None -> None
;;

let hand_of_player state player =
  List.filter_map (Player.get_hand player) ~f:(fun card_id ->
    Game_state.Card_registry.find state.Game_state.card_registry card_id
    |> Or_error.ok)
;;

let hand_counts_event (state : Game_state.t) =
  Action.Server_to_client.Hand_counts
    { counts =
        List.map state.players ~f:(fun p ->
          Player.get_name p, List.length (Player.get_hand p))
    }
;;

let send_hands (room : Room.t) state =
  List.iter state.Game_state.players ~f:(fun player ->
    match Hashtbl.find room.clients (Player.get_name player) with
    | None -> ()
    | Some client ->
      let hand = hand_of_player state player in
      if not (Pipe.is_closed client.writer)
      then
        Pipe.write_without_pushback
          client.writer
          (Action.Server_to_client.Hand_updated { your_hand = hand }))
;;

let broadcast_game_started (room : Room.t) state =
  let player_names = List.map state.Game_state.players ~f:Player.get_name in
  let current_player_name =
    Option.value (name_of_player_id state state.Game_state.turn) ~default:""
  in
  List.iter state.Game_state.players ~f:(fun player ->
    match Hashtbl.find room.clients (Player.get_name player) with
    | None -> ()
    | Some client ->
      if not (Pipe.is_closed client.writer)
      then
        Pipe.write_without_pushback
          client.writer
          (Action.Server_to_client.Game_started
             { your_hand = hand_of_player state player
             ; top_card = state.Game_state.top_card
             ; current_color = state.Game_state.current_color
             ; player_names
             ; current_player_name
             ; pending_draws = state.Game_state.pending_draws
             }));
  broadcast room (hand_counts_event state)
;;

(* Chooses an action for a bot-controlled player: plays the first valid card
   in hand, declaring a real color for wilds, or draws if nothing is
   playable. *)
let bot_action state player_name =
  let fallback = Action.Client_to_server.Draw in
  match player_id_of_name state player_name with
  | None -> fallback
  | Some player_id ->
    (match List.nth state.Game_state.players player_id with
     | None -> fallback
     | Some player ->
       let hand = hand_of_player state player in
       (match
          Game_rules.choose_card
            ~hand
            ~top_card:state.Game_state.top_card
            ~current_color:state.Game_state.current_color
        with
        | None -> fallback
        | Some card ->
          let declared_color =
            match card.Card.value with
            | Wild | Wild4 ->
              (* a wild's own color is NoColor, so declare a real one from
                 hand *)
              let color =
                List.find_map hand ~f:(fun c ->
                  match c.Card.color with
                  | NoColor -> None
                  | color -> Some color)
                |> Option.value ~default:Card.Color.Red
              in
              Some color
            | _ -> None
          in
          Action.Client_to_server.Play
            { card_id = Card.get_id card; declared_color }))
;;

let maybe_schedule_bot (room : Room.t) next_state current_player_name =
  match Hashtbl.find room.clients current_player_name with
  | Some client when client.is_bot ->
    let bot_turn = next_state.Game_state.turn in
    don't_wait_for
      (let%map () = Clock_ns.after (Time_ns.Span.of_sec 5.0) in
       match room.game_state with
       | None -> ()
       | Some verified_state ->
         if Int.equal verified_state.Game_state.turn bot_turn
            && Option.is_none verified_state.Game_state.winner
         then (
           Core.print_s
             [%message
               "Bot execution triggered"
                 (room.code : string)
                 (current_player_name : string)];
           Pipe.write_without_pushback
             room.request_writer
             { Queued_request.player_name = current_player_name
             ; action = bot_action verified_state current_player_name
             ; enqueued_at = Time_ns.now ()
             }))
  | _ -> ()
;;

(* a room with nobody in it and no running game can be forgotten *)
let maybe_remove_room t (room : Room.t) =
  if Hashtbl.is_empty room.clients && Option.is_none room.game_state
  then (
    Hashtbl.remove t.rooms room.code;
    Pipe.close room.request_writer;
    Core.print_s [%message "Room closed" (room.code : string)])
;;

(* per-room engine loop pulling actions off the room's pipe *)
let start_engine_loop t (room : Room.t) request_reader =
  don't_wait_for
    (Pipe.iter_without_pushback
       request_reader
       ~f:(fun { Queued_request.player_name; action; enqueued_at = _ } ->
         Core.print_s
           [%message
             "Processing Action"
               (room.code : string)
               (player_name : string)
               (action : Action.Client_to_server.t)];
         match room.game_state with
         | None -> ()
         | Some current_state ->
           (match player_id_of_name current_state player_name with
            | None -> ()
            | Some player_id ->
              (match
                 Rule_engine.apply_action
                   room.ruleset
                   current_state
                   ~player_id
                   ~action
               with
               | Error e ->
                 Core.print_s
                   [%message
                     "Rejected action" (player_name : string) (e : Error.t)];
                 (* tell the player who clicked; nobody else needs to know *)
                 (match Hashtbl.find room.clients player_name with
                  | Some client when not (Pipe.is_closed client.writer) ->
                    Pipe.write_without_pushback
                      client.writer
                      (Action.Server_to_client.Action_rejected
                         { reason = Error.to_string_hum e })
                  | _ -> ())
               | Ok next_state ->
                 room.game_state <- Some next_state;
                 broadcast
                   room
                   (Action.Server_to_client.Pile_updated
                      { top_card = next_state.top_card
                      ; current_color = next_state.current_color
                      ; pending_draws = next_state.pending_draws
                      });
                 send_hands room next_state;
                 broadcast room (hand_counts_event next_state);
                 (match List.nth next_state.players player_id with
                  | Some p when Int.equal (List.length (Player.get_hand p)) 1
                    ->
                    broadcast
                      room
                      (Action.Server_to_client.Uno_called
                         { player_name = Player.get_name p })
                  | _ -> ());
                 (match next_state.winner with
                  | Some winner_id ->
                    (match name_of_player_id next_state winner_id with
                     | Some winner_name ->
                       broadcast
                         room
                         (Action.Server_to_client.Game_over { winner_name });
                       room.game_state <- None;
                       Hashtbl.filter_inplace room.clients ~f:(fun client ->
                         not client.is_bot);
                       broadcast
                         room
                         (Action.Server_to_client.Lobby_updated
                            { players = Hashtbl.keys room.clients });
                       maybe_remove_room t room
                     | None -> ())
                  | None ->
                    (match name_of_player_id next_state next_state.turn with
                     | None -> ()
                     | Some current_player_name ->
                       broadcast
                         room
                         (Action.Server_to_client.Turn_changed
                            { current_player_name });
                       maybe_schedule_bot room next_state current_player_name))))))
;;

let code_alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ"

let generate_code t =
  let rec attempt () =
    let code =
      String.init 4 ~f:(fun _ ->
        code_alphabet.[Random.State.int t.random (String.length code_alphabet)])
    in
    if Hashtbl.mem t.rooms code then attempt () else code
  in
  attempt ()
;;

let create_room t =
  let code = generate_code t in
  let request_reader, request_writer = Pipe.create () in
  Pipe.set_size_budget request_writer request_queue_size_budget;
  let room =
    { Room.code
    ; clients = String.Table.create ()
    ; game_state = None
    ; ruleset = t.default_ruleset
    ; request_writer
    }
  in
  Hashtbl.set t.rooms ~key:code ~data:room;
  start_engine_loop t room request_reader;
  Core.print_s [%message "Room created" (code : string)];
  room
;;

let start ?(ruleset = Rule_engine.Ruleset.default) ~port () =
  Core.print_endline
    (Core.sprintf "\n>>> Booting Uno Server on port %d..." port);
  Core.Out_channel.flush Core.stdout;
  let t =
    { rooms = String.Table.create ()
    ; default_ruleset = ruleset
    ; random = Random.State.make_self_init ()
    }
  in
  let in_room (state : Connection_state.t) =
    match state.player_name, state.room with
    | Some name, Some room -> Ok (name, room)
    | _ -> Or_error.error_string "Not in a room yet"
  in
  let implementations =
    Rpc.Implementations.create_exn
      ~implementations:
        [ Rpc.Rpc.implement Rpc_protocol.create_room_rpc (fun _state () ->
            let room = create_room t in
            return (Ok room.Room.code))
        ; Rpc.Rpc.implement
            Rpc_protocol.join_lobby_rpc
            (fun state { Rpc_protocol.Join_query.code; player_name = name } ->
               let code = String.uppercase (String.strip code) in
               match Hashtbl.find t.rooms code with
               | None ->
                 return
                   (Or_error.error_string
                      "No room with that code (it may have closed)")
               | Some room ->
                 if Option.is_some room.game_state
                 then
                   return
                     (Or_error.error_string
                        "Cannot join: a game is in progress in this room")
                 else if String.is_empty (String.strip name)
                 then return (Or_error.error_string "Invalid name")
                 else (
                   match state.Connection_state.player_name with
                   | Some _ ->
                     return
                       (Or_error.error_string
                          "Already registered on this connection")
                   | None ->
                     if Hashtbl.mem room.clients name
                     then
                       return
                         (Or_error.error_string
                            "Username already taken in this room")
                     else (
                       state.player_name <- Some name;
                       state.room <- Some room;
                       Core.print_s
                         [%message
                           "Lobby Registration"
                             (room.code : string)
                             (name : string)];
                       broadcast
                         room
                         (Action.Server_to_client.Lobby_updated
                            { players = Hashtbl.keys room.clients });
                       return (Ok ()))))
        ; Rpc.Pipe_rpc.implement
            Rpc_protocol.game_stream_rpc
            (fun state () ->
               match in_room state with
               | Error e -> return (Error e)
               | Ok (name, room) ->
                 if Option.is_some room.game_state
                 then
                   return
                     (Error
                        (Error.of_string
                           "Access denied: Game is already in progress!"))
                 else (
                   let reader, writer = Pipe.create () in
                   let connection =
                     { Client_connection.name; writer; is_bot = false }
                   in
                   Hashtbl.set room.clients ~key:name ~data:connection;
                   (* everyone in the room learns about the newcomer *)
                   broadcast
                     room
                     (Action.Server_to_client.Lobby_updated
                        { players = Hashtbl.keys room.clients });
                   return (Ok reader)))
        ; Rpc.Rpc.implement Rpc_protocol.get_state_rpc (fun state () ->
            match in_room state with
            | Error e -> return (Error e)
            | Ok (name, room) ->
              let lobby_snapshot () =
                [ Action.Server_to_client.Lobby_updated
                    { players = Hashtbl.keys room.clients }
                ]
              in
              (match room.game_state with
               | None -> return (Ok (lobby_snapshot ()))
               | Some game ->
                 (match
                    List.find game.Game_state.players ~f:(fun p ->
                      String.equal (Player.get_name p) name)
                  with
                  | None -> return (Ok (lobby_snapshot ()))
                  | Some player ->
                    let current_player_name =
                      Option.value
                        (name_of_player_id game game.Game_state.turn)
                        ~default:""
                    in
                    return
                      (Ok
                         [ Action.Server_to_client.Game_started
                             { your_hand = hand_of_player game player
                             ; top_card = game.Game_state.top_card
                             ; current_color = game.Game_state.current_color
                             ; player_names =
                                 List.map game.Game_state.players ~f:Player.get_name
                             ; current_player_name
                             ; pending_draws = game.Game_state.pending_draws
                             }
                         ; hand_counts_event game
                         ]))))
        ; Rpc.Rpc.implement Rpc_protocol.submit_rules_rpc
            (fun state rules_text ->
               match in_room state with
               | Error e -> return (Error e)
               | Ok (player_name, room) ->
                 if Option.is_some room.game_state
                 then
                   return
                     (Or_error.error_string
                        "Cannot change rules while a game is in progress")
                 else (
                   match Rule_parser.parse_ruleset rules_text with
                   | Error e -> return (Error e)
                   | Ok rules ->
                     room.ruleset <- rules;
                     let num_rules = List.length rules in
                     Core.print_s
                       [%message
                         "Rules updated"
                           (room.code : string)
                           (player_name : string)
                           (num_rules : int)];
                     broadcast
                       room
                       (Action.Server_to_client.Rules_updated
                          { player_name; num_rules });
                     return (Ok ())))
        ; Rpc.Rpc.implement Rpc_protocol.take_action_rpc (fun state action ->
            match in_room state with
            | Error e -> return (Error e)
            | Ok (player_name, room) ->
              let queued =
                { Queued_request.player_name
                ; action
                ; enqueued_at = Time_ns.now ()
                }
              in
              let%map () = Pipe.write_if_open room.request_writer queued in
              Ok ())
        ; Rpc.Rpc.implement Rpc_protocol.start_game_rpc (fun state () ->
            match in_room state with
            | Error e -> return (Error e)
            | Ok (_name, room) ->
              if Option.is_some room.game_state
              then return (Or_error.error_string "Game already in progress")
              else (
                let player_names = Hashtbl.keys room.clients in
                if List.length player_names < 2
                then return (Or_error.error_string "Need at least 2 players")
                else (
                  match Game_state.create ~player_names ~hand_size:7 () with
                  | Error e -> return (Error e)
                  | Ok initial_state ->
                    room.game_state <- Some initial_state;
                    broadcast_game_started room initial_state;
                    return (Ok ()))))
        ]
      ~on_unknown_rpc:`Close_connection
      ~on_exception:Log_on_background_exn
  in
  let%map tcp_server =
    Rpc.Connection.serve
      ~implementations
      ~initial_connection_state:(fun _addr _conn ->
        let state = { Connection_state.player_name = None; room = None } in
        don't_wait_for
          (let%bind () = Rpc.Connection.close_finished _conn in
           match state.Connection_state.player_name, state.room with
           | Some name, Some room ->
             if Option.is_some room.game_state
             then (
               match Hashtbl.find room.clients name with
               | None -> ()
               | Some client ->
                 client.is_bot <- true;
                 Core.print_s
                   [%message
                     "Player dropped mid-game. Bot activated."
                       (room.code : string)
                       (name : string)];
                 (match room.game_state with
                  | Some game
                    when Option.equal
                           String.equal
                           (name_of_player_id game game.Game_state.turn)
                           (Some name) ->
                    maybe_schedule_bot room game name
                  | _ -> ()))
             else (
               Hashtbl.remove room.clients name;
               Core.print_s
                 [%message
                   "Player left the lobby"
                     (room.code : string)
                     (name : string)];
               broadcast
                 room
                 (Action.Server_to_client.Lobby_updated
                    { players = Hashtbl.keys room.clients });
               maybe_remove_room t room);
             Deferred.unit
           | _ -> Deferred.unit);
        state)
      ~where_to_listen:(Tcp.Where_to_listen.of_port port)
      ()
  in
  Core.print_endline ">>> SUCCESS: TCP socket listening. Ready for players.";
  Core.Out_channel.flush Core.stdout;
  tcp_server
;;
