open! Core 

type t =
    | Clockwise
    | Counter
  [@@deriving sexp, compare, equal, bin_io]