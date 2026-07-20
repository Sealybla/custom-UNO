open! Core

module Color = struct
  type t = 
  | Red
  | Green
  | Blue
  | Yellow
  | NoColor
  [@@deriving enumerate]

end

module Effect = struct
  type t = 
  | Skip
  | Plus
  | Reverse
  | NoEffect
  | Wild
  | Wild4
  [@@deriving enumerate]

end

type t = 
{ 
  color:Color.t;
  effect: Effect.t
}[@@deriving sexp_of]