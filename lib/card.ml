open! Core

module Color = struct
  type t = 
  | Red
  | Green
  | Blue
  | Yellow
  | NoColor
  [@@deriving enumerate, sexp, compare, equal, bin_io]

end

module Effect = struct
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
  [@@deriving enumerate, sexp, compare, equal, bin_io]

end

type t = 
{ 
  color:Color.t;
  effect: Effect.t;
  id : Int.t
}[@@deriving sexp, compare, equal, bin_io]
