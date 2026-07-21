open! Core 
open! Async

type 'a bin_type_class = 'a Bin_prot.Type_class.t

(* steam of all real-time game updates *)
let game_stream_rpc = 
  Rpc.Pipe_rpc.create 
    ~name:"game-stream"
    ~version: 1
    ~bin_query: Unit.bin_t
    ~bin_response: Action.Server_to_client.bin_t
    ~bin_error:Error.bin_t
    ()
;;

(* handles a player joining the lobby *)
let join_lobby_rpc =
  Rpc.Rpc.create
  ~name:"join-lobby"
  ~version:1
  ~bin_query:String.bin_t
  ~bin_response:[%bin_type_class: unit Or_error.t]
  ~include_in_error_count:Only_on_exn
;;

(* forward players moves to game engine *) 
let take_action_rpc =
  Rpc.Rpc.create
  ~name:"take-action"
  ~version:1
  ~bin_query:Action.Client_to_server.bin_t
  ~bin_response:[%bin_type_class: unit Or_error.t]
  ~include_in_error_count:Only_on_exn
;;