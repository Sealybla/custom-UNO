open! Core

type t = 
{ id : int
; name : string
; hand: Card.t list
} [@@deriving sexp, compare, equal, bin_io]