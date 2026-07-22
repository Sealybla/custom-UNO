open! Core

(* Game State mutations caused by rule executions ADD AS SUBMODULE TO
   GAMESTATE LATER *)

type t =
  | SetTopCard of Card.t
  | SetActiveColor of Card.Color.t
  | AddPendingDraws of int
  | ExecuteDraw of
      { player : Player.t
      ; count : int
      }
  | ReverseDirection
  | AdvanceTurn
