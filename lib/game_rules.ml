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

(* adjust this funcetion later to make it customizable *)
let get_next_turn ~current_turn ~player_count ~direction ~effect =
  let step =
    match direction with
    | Game_state.Direction.Clockwise -> 1
    | Game_state.Direction.Counter -> -1
  in
  let multiplier = match effect with Card.Value.Skip -> 2 | _ -> 1 in
  let total_shift = step * multiplier in
  Core.Int.rem (current_turn + total_shift + player_count) player_count
;;

(* adjust this function to make it customizable *)
let get_next_direction ~player_count ~direction ~effect =
  match effect with
  | Card.Value.Reverse when player_count > 2 ->
    (match direction with
     | Game_state.Direction.Clockwise -> Game_state.Direction.Counter
     | Game_state.Direction.Counter -> Game_state.Direction.Clockwise)
  | _ -> direction
;;

let is_vulnerable_to_uno_penalty ~hand_size ~declared_uno =
  Int.equal hand_size 1 && not declared_uno
;;
