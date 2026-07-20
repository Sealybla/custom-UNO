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
; current_color : Card.Color.t
; direction : Direction.t
; turn: int
}

let create_card_queue (): Card.t Queue.t =
  let arr = 
  in 
  let q = Queue.of_array arr in
  q
;;

