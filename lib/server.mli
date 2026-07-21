open! Core
open! Async

(** The global, single-threaded multiplayer Uno coordinator handle. *)
type t

(**  binds a TCP stream to the designated port, initializes the 
    internal action budget queue, and provisions background loops. *)
val start : port:int -> unit -> t Deferred.t

(** Broadcasts a game protocol event manually to every active table slot. *)
val broadcast : t -> Action.Server_to_client.t -> unit
