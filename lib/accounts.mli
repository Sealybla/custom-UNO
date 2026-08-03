open! Core

(* Optional player accounts for the web UI: logging in gives you a personal
   library of named rule "modes" (saved rule texts). Persisted as one sexp
   file (see [Snapshot]); passwords are salted-MD5 - a speed bump for a card
   game, not real security. *)

module Mode : sig
  type t =
    { name : string
    ; rules_text : string
    }
  [@@deriving sexp, compare, equal]
end

type t

(* [random_state] seeds salt generation; tests pass one for determinism *)
val create : ?random_state:Random.State.t -> unit -> t

(* the whole store, for saving to / loading from disk *)
module Snapshot : sig
  type t [@@deriving sexp]
end

val snapshot : t -> Snapshot.t
val of_snapshot : ?random_state:Random.State.t -> Snapshot.t -> t

(* log in, creating the account on first sight of the username. Returns
   whether it was created, the display name, and the saved modes. *)
val login
  :  t
  -> username:string
  -> password:string
  -> ([ `Created | `Logged_in ] * string * Mode.t list) Or_error.t

val modes : t -> username:string -> Mode.t list

(* save the editor's text under a name; a same-named mode is replaced *)
val save_mode
  :  t
  -> username:string
  -> mode_name:string
  -> rules_text:string
  -> Mode.t list Or_error.t

val delete_mode : t -> username:string -> mode_name:string -> Mode.t list Or_error.t
