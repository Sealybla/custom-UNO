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

(* creates a fresh room and returns its join code *)
let create_room_rpc =
  Rpc.Rpc.create
    ~name:"create-room"
    ~version:1
    ~bin_query:Unit.bin_t
    ~bin_response:[%bin_type_class: String.t Or_error.t]
    ~include_in_error_count:Only_on_exn
;;

module Join_query = struct
  type t =
    { code : String.t
    ; player_name : String.t
    }
  [@@deriving sexp, bin_io]
end

(* handles a player joining a room's lobby by code *)
let join_lobby_rpc =
  Rpc.Rpc.create
  ~name:"join-lobby"
  ~version:2
  ~bin_query:Join_query.bin_t
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

(* personalized snapshot of the current lobby/game as a replayable event
   list, for clients that (re)connect mid-session *)
let get_state_rpc =
  Rpc.Rpc.create
    ~name:"get-state"
    ~version:1
    ~bin_query:Unit.bin_t
    ~bin_response:[%bin_type_class: Action.Server_to_client.t List.t Or_error.t]
    ~include_in_error_count:Only_on_exn
;;

(* replace the lobby's ruleset with parsed rule text before a game starts *)
let submit_rules_rpc =
  Rpc.Rpc.create
    ~name:"submit-rules"
    ~version:1
    ~bin_query:String.bin_t
    ~bin_response:[%bin_type_class: unit Or_error.t]
    ~include_in_error_count:Only_on_exn
;;

(* starts uno game *)
let start_game_rpc =
  Rpc.Rpc.create
    ~name:"start-game"
    ~version:1
    ~bin_query:Unit.bin_t
    ~bin_response:[%bin_type_class: unit Or_error.t]
    ~include_in_error_count:Only_on_exn
;;
(* toggle the caller's lobby ready flag; the game can only start when
   every player in the room is ready *)
let set_ready_rpc =
  Rpc.Rpc.create
    ~name:"set-ready"
    ~version:1
    ~bin_query:Bool.bin_t
    ~bin_response:[%bin_type_class: unit Or_error.t]
    ~include_in_error_count:Only_on_exn
;;
