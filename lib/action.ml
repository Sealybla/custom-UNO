open !Core
open Card

type t = 
  | Play of Card.t
  | Choose of Card.Color.t 
  | Draw
  | Uno 
  | Quit
[@@deriving sexp, compare, equal, bin_io]

