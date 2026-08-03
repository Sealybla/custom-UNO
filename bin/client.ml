open! Core
open! Async
open! Custom_uno

let print_event (event : Action.Server_to_client.t) =
  match event with
  | Lobby_updated { players; ready_players; last_winner } ->
    print_s
      [%message
        "lobby"
          (players : string list)
          (ready_players : string list)
          (last_winner : string option)]
  | Game_started
      { your_hand; top_card; current_color; player_names; current_player_name
      ; pending_draws; stacking_enabled
      } ->
    print_endline "=== game started ===";
    print_s [%message (player_names : string list) (stacking_enabled : bool)];
    print_s
      [%message
        (top_card : Card.t) (current_color : Card.Color.t) (pending_draws : int)];
    print_s [%message "your hand" (your_hand : Card.t list)];
    print_s [%message "turn" (current_player_name : string)]
  | Hand_updated { your_hand; playable_ids = _ } ->
    print_s [%message "your hand" (your_hand : Card.t list)]
  | Pile_updated { top_card; current_color; pending_draws } ->
    print_s
      [%message
        "pile"
          (top_card : Card.t)
          (current_color : Card.Color.t)
          (pending_draws : int)]
  | Turn_changed { current_player_name; can_pass; stack_value } ->
    print_s
      [%message
        "turn"
          (current_player_name : string)
          (can_pass : bool)
          (stack_value : Card.Value.t option)]
  | Game_over { winner_name } ->
    print_s [%message "GAME OVER" (winner_name : string)]
  | Hand_counts { counts } ->
    print_s [%message "hand counts" (counts : (string * int) list)]
  | Uno_called { player_name } ->
    print_s [%message "UNO!" (player_name : string)]
  | Uno_penalty { player_name; count; caught } ->
    print_s
      [%message
        (if caught then "caught without calling UNO" else "bad UNO call")
          (player_name : string)
          (count : int)]
  | Turn_countdown { player_name; seconds } ->
    print_s [%message "turn countdown" (player_name : string) (seconds : int)]
  | Rules_updated { player_name; num_rules; rules_text = _ } ->
    print_s [%message "rules updated" (player_name : string) (num_rules : int)]
  | Action_rejected { reason } -> print_s [%message "rejected" (reason : string)]
  | Player_skipped { player_name } ->
    print_s [%message "skipped" (player_name : string)]
  | Forced_draw { player_name; count } ->
    print_s [%message "forced to draw" (player_name : string) (count : int)]
  | Direction_changed { direction } ->
    print_s [%message "direction" (direction : Direction.t)]
;;

let color_of_string = function
  | "red" -> Some Card.Color.Red
  | "green" -> Some Card.Color.Green
  | "blue" -> Some Card.Color.Blue
  | "yellow" -> Some Card.Color.Yellow
  | _ -> None
;;

let handle_line conn line =
  match String.split (String.strip line) ~on:' ' with
  | [ "start" ] ->
    let%map result = Rpc.Rpc.dispatch_exn Rpc_protocol.start_game_rpc conn () in
    (match result with
     | Ok () -> ()
     | Error e -> print_s [%message "error" (e : Error.t)])
  | [ "draw" ] ->
    let%map result =
      Rpc.Rpc.dispatch_exn Rpc_protocol.take_action_rpc conn Action.Client_to_server.Draw
    in
    (match result with
     | Ok () -> ()
     | Error e -> print_s [%message "error" (e : Error.t)])
  | [ "pass" ] ->
    let%map result =
      Rpc.Rpc.dispatch_exn Rpc_protocol.take_action_rpc conn Action.Client_to_server.Pass
    in
    (match result with
     | Ok () -> ()
     | Error e -> print_s [%message "error" (e : Error.t)])
  | [ "uno" ] ->
    let%map result =
      Rpc.Rpc.dispatch_exn
        Rpc_protocol.take_action_rpc
        conn
        Action.Client_to_server.Call_uno
    in
    (match result with
     | Ok () -> ()
     | Error e -> print_s [%message "error" (e : Error.t)])
  | [ (("ready" | "unready") as word) ] ->
    let%map result =
      Rpc.Rpc.dispatch_exn
        Rpc_protocol.set_ready_rpc
        conn
        (String.equal word "ready")
    in
    (match result with
     | Ok () -> ()
     | Error e -> print_s [%message "error" (e : Error.t)])
  | [ "rules"; path ] ->
    (match%bind Monitor.try_with (fun () -> Reader.file_contents path) with
     | Error exn ->
       print_s
         [%message
           "cannot read file"
             (path : string)
             ~error:(Exn.to_string (Monitor.extract_exn exn) : string)];
       Deferred.unit
     | Ok text ->
       let%map result =
         Rpc.Rpc.dispatch_exn Rpc_protocol.submit_rules_rpc conn text
       in
       (match result with
        | Ok () -> print_endline "rules accepted"
        | Error e -> print_s [%message "rules rejected" (e : Error.t)]))
  | "play" :: id :: rest ->
    (match Int.of_string_opt id with
     | None ->
       print_endline "usage: play <card_id> [color]";
       Deferred.unit
     | Some card_id ->
       let declared_color =
         match rest with
         | [ c ] -> color_of_string c
         | _ -> None
       in
       let%map result =
         Rpc.Rpc.dispatch_exn
           Rpc_protocol.take_action_rpc
           conn
           (Action.Client_to_server.Play { card_id; declared_color })
       in
       (match result with
        | Ok () -> ()
        | Error e -> print_s [%message "error" (e : Error.t)]))
  | [ "" ] -> Deferred.unit
  | _ ->
    print_endline
      "commands: ready | unready | start | draw | pass | play <card_id> [red|green|blue|yellow] | rules <file>";
    Deferred.unit
;;

let run ~host ~port ~name ~room ~create_room =
  let%bind conn =
    Rpc.Connection.client (Tcp.Where_to_connect.of_host_and_port { host; port })
    >>| Result.ok_exn
  in
  let%bind code =
    match room, create_room with
    | Some code, _ -> return (String.uppercase code)
    | None, true ->
      let%map code =
        Rpc.Rpc.dispatch_exn Rpc_protocol.create_room_rpc conn () >>| ok_exn
      in
      print_s [%message "room created" (code : string)];
      code
    | None, false ->
      failwith "pass -room CODE to join a room, or -host to create one"
  in
  let%bind () =
    Rpc.Rpc.dispatch_exn
      Rpc_protocol.join_lobby_rpc
      conn
      { Rpc_protocol.Join_query.code; player_name = name }
    >>| ok_exn
  in
  print_s [%message "joined lobby" (code : string)];
  let%bind reader, _md =
    Rpc.Pipe_rpc.dispatch_exn Rpc_protocol.game_stream_rpc conn ()
  in
  don't_wait_for (Pipe.iter_without_pushback reader ~f:print_event);
  print_endline "commands: ready | unready | start | draw | pass | play <card_id> [color] | rules <file>";
  Pipe.iter (Reader.lines (Lazy.force Reader.stdin)) ~f:(handle_line conn)
;;

let command =
  Command.async
    ~summary:"Terminal client for Uno"
    (let open Command.Let_syntax in
     let%map_open name = flag "-name" (required string) ~doc:"string your player name"
     and port = flag "-port" (optional_with_default 8080 int) ~doc:"int server port"
     and host =
       flag "-server" (optional_with_default "localhost" string) ~doc:"string server host"
     and room = flag "-room" (optional string) ~doc:"CODE room code to join"
     and create_room = flag "-host" no_arg ~doc:" create a new room and print its code"
     in
     fun () -> run ~host ~port ~name ~room ~create_room)
;;

let () = Command_unix.run command