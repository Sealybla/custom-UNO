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

(*= let create () =
  { players = []
  ; draw_pile = Queue.create ()
  ; played_pile = []
  ; top_card = None
  ; current_color = Blue (* default, changes according to top card *)
  ; direction = Clockwise
  ; turn = 0
  }
;; *)

(* helper function for start state *)
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

(* helper function that takes ANY array of cards, shuffles, and adds to draw
   pile *)
let reshuffle_add_to_draw t arr : unit =
  Array.permute arr;
  Array.iter arr ~f:(fun card -> Queue.enqueue t.draw_pile card)
;;

(* reshuffles play pile and adds to draw pile *)
let play_to_draw_pile t : unit =
  let arr = List.to_array t.played_pile in
  reshuffle_add_to_draw t arr
;;

(* helper function *)
let draw_card t : Card.t Or_error.t =
  match Queue.dequeue t.draw_pile with
  | Some c -> Ok c
  | None ->
    (match List.is_empty t.played_pile with
     | true -> Or_error.error_string "No cards left to reshuffle with..."
     | false ->
       play_to_draw_pile t;
       Ok (Queue.dequeue_exn t.draw_pile))
;;

(* helper function *)
let draw_card_exn t : Card.t = Queue.dequeue_exn t.draw_pile

(* draws top card in draw pile, reshuffles card if no cards left in draw pile
   return error if no player exists or no playable cards *)
let draw_card_player t player_id : unit Or_error.t =
  let%bind player =
    match List.nth t.players player_id with
    | Some p -> Ok p
    | None -> Or_error.error_string "Player ID NOT FOUND"
  in
  let%bind top_card_id = draw_card t in
  Ok (Player.add_card player (Card.get_id top_card_id))
;;

(* same as draw_card_player without exception, used at start *)
let draw_card_player_exn t player_id : unit =
  let player = List.nth_exn t.players player_id in
  let top_card_id = draw_card_exn t in
  Player.add_card player (Card.get_id top_card_id)
;;

(* helper function *)
let update_top_card (state : t) (new_card : Card.t) : t =
  { state with top_card = new_card }
;;

(* Initializes card deck, adds to draw pile, distributes cards to player list
   and returns new game state. Assumes player list is nonempty, with each
   player having empty hands *)
let start_distribution t hand_size deck_size : t =
  let () = reshuffle_add_to_draw t (create_card_array deck_size) in
  let () =
    (* giving all players 7 cards at once is same as one at a time *)
    List.iter t.players ~f:(fun player ->
      for _ = 1 to hand_size do
        draw_card_player_exn t (Player.get_id player)
      done)
  in
  let top_card = draw_card_exn t in
  update_top_card t top_card
;;
