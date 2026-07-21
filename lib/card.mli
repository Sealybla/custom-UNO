open! Core

module Color : sig
  type t =
    | Red
    | Green
    | Blue
    | Yellow
    | NoColor
  [@@deriving sexp, compare, equal, bin_io]
end

module Effect : sig
  type t =
    | Skip
    | Plus
    | Reverse
    | NoEffect
    | Wild
    | Wild4
  [@@deriving sexp, compare, equal, bin_io]
end

type t = {
  color: Color.t;
  effect: Effect.t;
  id : Int.t;
} [@@deriving sexp, compare, equal, bin_io]
