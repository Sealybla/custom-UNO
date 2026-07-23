open! Core

type t =
  | CardPlayed of
      { player : Player.t
      ; card : Card.t
      }
  | DrawRequested of { player : Player.t }
  | TurnStarted of { player : Player.t }
