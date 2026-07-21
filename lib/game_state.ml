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
  let cards = ref [] in
  let i = ref 0 in 
  let add_cards color effect = 
    let c1 = {color; effect; id = !i} in 
    Int.incr i;
    let c2 = {color; effect; id = !i} in
    Int.incr i; 
    cards := c1:: c2 :: !cards
  in
  List.iter Card.Color.all ~f:(fun col -> 
    List.iter Card.effect.all ~f:(fun eff -> 
      match col, eff with 
      | (Red | Green | Blue |Yellow), (Wild | Wild4) -> ()
      | (Red | Green | Blue | Yellow), _ -> add_cards col eff
      | NoColor, (Wild | Wild4) -> add_cards col eff
      | NoColor, _ -> ()));
  let arr = Array.of_list !cards in 
  Array.shuffle arr;
  Queue.of_array arr
;;

