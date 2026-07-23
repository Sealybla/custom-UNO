open! Core

let is_valid_play ~top_card ~played_card ~current_color =
  match played_card.Card.value with
  | Card.Value.Wild | Card.Value.Wild4 -> true
  | _ ->
    Card.Color.equal played_card.color current_color
    || Card.Value.equal played_card.value top_card.Card.value
;;

(* adjust this function late on to make it customizable for custom rules *)
let calculate_draw_penalty = function
  | Card.Value.Plus -> 2
  | Card.Value.Wild4 -> 4
  | _ -> 0
;;

  (* adjust this funcetion later to make it customizable*)
  let get_next_turn ~current_turn ~player_count ~direction ~effect =
    let step =
      match direction with 
      | Direction.Clockwise -> 1
      | Direction.Counter -> -1
    in
    let multiplier = 
      match effect with 
      | Card.Value.Skip -> 2
      | Card.Value.Reverse when Int.equal player_count 2 -> 2
      | _ -> 1
    in 
    let total_shift = step * multiplier in

    Core.Int.rem (current_turn + total_shift + ( player_count * 2)) player_count

(*adjust this function to make it customizable*)
let get_next_direction  ~player_count ~direction ~effect =
  match effect with 
  | Card.Value.Reverse when player_count > 2 -> 
    (match direction with 
    | Direction.Clockwise -> Direction.Counter
    | Direction.Counter -> Direction.Clockwise)
  | _ -> direction
;;

  
(* picks first playable card in hand or None if nothing is playable *)
  (* for bots*) 
let choose_card ~hand ~top_card ~current_color = 
  List.find hand ~f:(fun card -> 
    is_valid_play ~top_card ~played_card:card ~current_color)
;;