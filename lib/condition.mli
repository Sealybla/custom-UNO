open! Core

type t =
  | Always
  | MatchesTopColor
  | MatchesTopValue
  | PendingDrawsGreaterThan of int
  | And of t * t
  | Or of t * t
  | Not of t
[@@deriving sexp, compare, equal, bin_io]

val eval : Game_state.t -> Event.t -> t -> bool
