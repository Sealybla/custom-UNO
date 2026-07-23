open! Core
open! Async
open! Custom_uno

let print_event (event : Action.Server_to_client.t) =
  match event with
  | Lobby_updated { players } ->
    print_s [%message "lobby" (players : string list)]
  | Game_started { your_hand; top_card; current_color; player_names; current_player_name } ->
    print_endline "=== game started ===";
    print_s [%message (player_names : string list)];
    print_s [%message (top_card : Card.t) (current_color : Card.Color.t)];
    print_s [%message "your hand" (your_hand : Card.t list)];
    print_s [%message "turn" (current_player_name : string)]
  | Hand_updated { your_hand } ->
    print_s [%message "your hand" (your_hand : Card.t list)]
  | Pile_updated { top_card; current_color } ->
    print_s [%message "pile" (top_card : Card.t) (current_color : Card.Color.t)]
  | Turn_changed { current_player_name } ->
    print_s [%message "turn" (current_player_name : string)]
  | Game_over { winner_name } ->
    print_s [%message "GAME OVER" (winner_name : string)]
  | Hand_counts { counts } ->
    print_s [%message "hand counts" (counts : (string * int) list)]
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
    print_endline "commands: start | draw | play <card_id> [red|green|blue|yellow]";
    Deferred.unit
;;

let run ~host ~port ~name =
  let%bind conn =
    Rpc.Connection.client (Tcp.Where_to_connect.of_host_and_port { host; port })
    >>| Result.ok_exn
  in
  let%bind () = Rpc.Rpc.dispatch_exn Rpc_protocol.join_lobby_rpc conn name >>| ok_exn in
  print_endline "joined lobby";
  let%bind reader, _md =
    Rpc.Pipe_rpc.dispatch_exn Rpc_protocol.game_stream_rpc conn ()
  in
  don't_wait_for (Pipe.iter_without_pushback reader ~f:print_event);
  print_endline "commands: start | draw | play <card_id> [color]";
  Pipe.iter (Reader.lines (Lazy.force Reader.stdin)) ~f:(handle_line conn)
;;

let command =
  Command.async
    ~summary:"Terminal client for Uno"
    (let open Command.Let_syntax in
     let%map_open name = flag "-name" (required string) ~doc:"string your player name"
     and port = flag "-port" (optional_with_default 8080 int) ~doc:"int server port"
     and host =
       flag "-host" (optional_with_default "localhost" string) ~doc:"string server host"
     in
     fun () -> run ~host ~port ~name)
;;

let () = Command_unix.run command