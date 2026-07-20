open! Core

module Color = struct
  type t = 
  | Red
  | Green
  | Blue
  | Yellow
  | NoColor

end

module Effect = struct
  type t = 
| Skip
| Plus
| Reverse
| NoEffect
| Wild
| Wild4

end

type t = 
{ 
  color:Color.t;
  effect: Effect.t
}