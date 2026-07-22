open! Core
open Or_error.Let_syntax

module Direction = struct
  type t =
    | Clockwise
    | Counter
  [@@deriving sexp, compare, equal, bin_io]
end

(* maps id to card for easy search bc hands only keep track of id *)
module Card_registry = struct
  type t =
    { mutable data : Card.t option Array.t
    ; mutable size : int
    }
  [@@deriving sexp, compare, equal, bin_io]

  let create capacity = { data = Array.create ~len:capacity None; size = 0 }

  (* assume size will never go over because this is only used internally *)
  let add_card_exn t card =
    t.data.(t.size) <- Some card;
    t.size <- t.size + 1
  ;;
end

(* draw_pile is mutable bc we want to be able to change the pile *)
type t =
  { players : Player.t list
  ; draw_pile : Card.t Queue.t (* played pile does not contain top card *)
  ; played_pile : Card.t List.t
  ; top_card : Card.t
  ; current_color : Card.Color.t
  ; direction : Direction.t
  ; turn : int
  }
[@@deriving sexp, compare, equal, bin_io]

let create_card_array deck_size : Card.t Array.t =
  let cards = ref [] in
  let i = ref 0 in
  let card_registry = Card_registry.create deck_size in
  let add_cards color effect =
    let c1 : Card.t = { color; effect; id = !i } in
    Int.incr i;
    Card_registry.add_card_exn card_registry c1;
    let c2 : Card.t = { color; effect; id = !i } in
    Int.incr i;
    Card_registry.add_card_exn card_registry c2;
    cards := c1 :: c2 :: !cards
  in
  List.iter Card.Color.all ~f:(fun col ->
    List.iter Card.Effect.all ~f:(fun eff ->
      match col, eff with
      | (Red | Green | Blue | Yellow), (Wild | Wild4) -> ()
      | (Red | Green | Blue | Yellow), _ -> add_cards col eff
      (* need to add 4 of each instead of 2 *)
      | NoColor, (Wild | Wild4) ->
        add_cards col eff;
        add_cards col eff
      | NoColor, _ -> ()));
  Array.of_list !cards
;;

let reshuffle_add_to_draw t arr =
  Array.permute arr;
  Array.iter arr ~f:(fun card -> Queue.enqueue t.draw_pile card)
;;

let play_to_draw_pile t : unit =
  let arr = List.to_array t.played_pile in
  reshuffle_add_to_draw t arr
;;

(* draws top card in draw pile, reshuffles card if no cards left in draw pile
   return error if *)
let draw_card t player_id : unit Or_error.t =
  let%bind player =
    match List.nth t.players player_id with
    | Some p -> Ok p
    | None -> Or_error.error_string "Player ID NOT FOUND"
  in
  let%bind top_card_id =
    match Queue.dequeue t.draw_pile with
    | Some c -> Ok c
    | None ->
      (match List.is_empty t.played_pile with
       | true -> Or_error.error_string "No cards left to reshuffle with..."
       | false ->
         play_to_draw_pile t;
         Ok (Queue.dequeue_exn t.draw_pile))
  in
  Ok (Player.add_card player (Card.get_id top_card_id))
;;

(* distirbutes cards to player list and returns draw pile Assumes player list
   is established with empty *)
(* let start_distribution t deck_size:unit = let card_queue = reshuffle_pile
   (create_card_queue deck_size) in () ;; *)
