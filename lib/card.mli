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
  | Wild
  | Wild4
  | One
  | Two 
  | Three
  | Four 
  | Five
  | Six
  | Seven
  | Eight
  | Nine 
  [@@deriving enumerate]
end   


