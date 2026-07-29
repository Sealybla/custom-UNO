open! Core
open! Async 
open! Custom_uno

let html_headers =
  Cohttp.Header.of_list [ "Content-Type", "text/html; charset=utf-8" ]

let handler _game ~body:_ _sock req =
  match Uri.path (Cohttp.Request.uri req) with
  | "/" -> Cohttp_async.Server.respond_string ~headers:html_headers Page.html
  | _ -> Cohttp_async.Server.respond `Not_found

(* no rules file means the built-in standard ruleset; a file that can't be
   read or parsed is fatal — better to die at boot than run the wrong rules *)
let load_ruleset rules_file =
  match rules_file with
  | None -> return Rule_engine.Ruleset.default
  | Some path ->
    let%map res = Monitor.try_with (fun () -> Reader.file_contents path) in
    (match res with
     | Error exn ->
       Core.eprintf
         ">>> Cannot read rules file '%s': %s\n"
         path
         (Exn.to_string (Monitor.extract_exn exn));
       Core.exit 1
     | Ok contents ->
       (match Rule_parser.parse_ruleset contents with
        | Error e ->
          Core.eprintf
            ">>> Invalid rules in '%s': %s\n"
            path
            (Error.to_string_hum e);
          Core.exit 1
        | Ok rules ->
          Core.printf
            ">>> Loaded %d custom rules from '%s'\n"
            (List.length rules)
            path;
          rules))

let run_server port rules_file =
  let%bind ruleset = load_ruleset rules_file in
  (* registers an accept loop with Async's scheduler and returns a Deferred.t *)
  let%bind game = Server.start ~ruleset ~port () in
  (* another register on same loop *) 
  let%bind _web =
    Cohttp_async.Server.create 
      ~on_handler_error:`Ignore
      (Tcp.Where_to_listen.of_port (port + 1))
      (handler game)
in
(* never resolves so keeps scheduler running *)
Deferred.never()

let command =
  Command.async 
    ~summary:"Launch the OCaml Multiplayer Uno Backend Server"
    (let open Command.Let_syntax in
    let%map_open port =
      flag "-port"
      (optional_with_default 8080 int)
      ~doc:"int Port number to host the game lobby on (default: 8080)"
    and rules_file =
      flag "-rules"
      (optional string)
      ~doc:"file Rule file to load (default: built-in standard rules)"
    in
    fun () -> run_server port rules_file)

let () = Command_unix.run command
