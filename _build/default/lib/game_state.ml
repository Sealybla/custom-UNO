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
<<<<<<< HEAD

let create_card_queue (): Card.t Queue.t =
  let arr = 
    Card.Color.all
  in 
  let q = Queue.of_array arr in
  q
;;

=======
>>>>>>> 5f0c8ce3c8b6183c91808cbd32636b1997c8df41
