open! Core

module Direction = struct
  type t = 
  | Clockwise
  | Counter 
end

type t = 
{ players : Player.t list
; draw_pile : Card.t Queue.t
; played_pile : Card.t Stack.t
; current_color : Color.t
; direction : 
; turn: 
}