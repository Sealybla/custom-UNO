open! Core
open! Async 
open! Custom_uno

let run_server port = 
  let%bind _server = Server.start ~port () in 
  Deferred.never ()

let command =
  Command.async 
    ~summary:"Launch the OCaml Multiplayer Uno Backend Server"
    (let open Command.Let_syntax in
    let%map_open port =
      flag "-port"
      (optional_with_default 8080 int) 
      ~doc:"int Port number to host the game lobby on (default: 8080)"
    in
    fun () -> run_server port)

let () = Command_unix.run command
