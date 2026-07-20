open! Core

type t [@@deriving sexp_of]

module Color: sig
    type t = 
  | Red
  | Green
  | Blue
  | Yellow
  | NoColor
  [@@deriving enumerate]
end  



module Effect : sig
  type t = 
  | Skip
  | Plus
  | Reverse
  | NoEffect
  | Wild
  | Wild4
  [@@deriving enumerate]
end   



(* 

val color: t -> Color.t *)
