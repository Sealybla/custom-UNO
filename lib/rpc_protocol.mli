open! Core
open! Async

type 'a bin_type_class = 'a Bin_prot.Type_class.t

(* steam of all real-time game updates *)
val game_stream_rpc : (Unit.t, Action.Server_to_client.t, Error.t) Rpc.Pipe_rpc.t

(* handles a player joining the lobby *)
val join_lobby_rpc : (String.t, unit Or_error.t) Rpc.Rpc.t

(* forward players moves to game engine *) 
val take_action_rpc : (Action.Client_to_server.t, unit Or_error.t) Rpc.Rpc.t

(* personalized snapshot of the current lobby/game as a replayable event
   list, for clients that (re)connect mid-session *)
val get_state_rpc
  : (Unit.t, Action.Server_to_client.t List.t Or_error.t) Rpc.Rpc.t

(* replace the lobby's ruleset with parsed rule text before a game starts *)
val submit_rules_rpc : (String.t, unit Or_error.t) Rpc.Rpc.t

val start_game_rpc : (Unit.t, unit Or_error.t) Rpc.Rpc.t