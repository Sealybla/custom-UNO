open! Core

(* basically player actions but for only during the game *)
type t =
  | CardPlayed of
      { player : Player.t
      ; card : Card.t
      }
  | DrawRequested of { player : Player.t }
  | TurnStarted of { player : Player.t }
