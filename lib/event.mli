open! Core

(* basically player actions but for only during the game *)
type t =
  | CardPlayed of
      { player : Player.t
      ; card : Card.t
      ; declared_color : Card.Color.t Option.t
      }
  | DrawRequested of { player : Player.t }
[@@deriving sexp, compare, equal, bin_io]

val of_client_action
  :  Game_state.t
  -> player:Player.t
  -> action:Action.Client_to_server.t
  -> t Or_error.t
