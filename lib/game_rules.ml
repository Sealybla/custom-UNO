open! Core

(* NoColor means no color is in force yet. The only way a game reaches that
   state is the flipped starting card being a wild, which nobody chose a
   color for - so the opening player may lead with whatever they like. *)
let matches_color ~(played_card : Card.t) ~(current_color : Card.Color.t) =
  match current_color with
  | NoColor -> true
  | color -> Card.Color.equal played_card.color color
;;

let is_valid_play ~top_card ~played_card ~current_color =
  match played_card.Card.value with
  | Card.Value.Wild | Card.Value.Wild4 -> true
  | _ ->
    matches_color ~played_card ~current_color
    || Card.Value.equal played_card.value top_card.Card.value
;;

(* picks first playable card in hand or None if nothing is playable *)
(* for bots *)
let choose_card ~hand ~top_card ~current_color =
  List.find hand ~f:(fun card ->
    is_valid_play ~top_card ~played_card:card ~current_color)
;;
