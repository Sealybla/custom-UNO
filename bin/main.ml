open! Core
open! Async 
open! Custom_uno

let html_headers =
  Cohttp.Header.of_list [ "Content-Type", "text/html; charset=utf-8" ]

let handler _game ~body:_ _sock req =
  match Uri.path (Cohttp.Request.uri req) with
  | "/" -> Cohttp_async.Server.respond_string ~headers:html_headers Page.html
  | _ -> Cohttp_async.Server.respond `Not_found

let run_server port = 
  let%bind game = Server.start ~port () in 
  let%bind _web =
    Cohttp_async.Server.create 
      ~on_handler_error:`Ignore
      (Tcp.Where_to_listen.of_port (port + 1))
      (handler game)
in
Deferred.never()

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
