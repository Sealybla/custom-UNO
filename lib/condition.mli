open! Core

type t =
  | Always
  | MatchesTopColor
  | MatchesTopValue
  | PendingDrawsGreaterThan of int
  | And of Condition.t * Condition.t
  | Or of Condition.t * Condition.t
  | Not of Condition.t
[@@deriving sexp, compare, equal, bin_io]

val eval : Game_state.t -> Event.t -> t -> bool
