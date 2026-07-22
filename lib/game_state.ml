open! Core
open Or_error.Let_syntax

(* direction of gameplay *)
module Direction = struct
  type t =
    | Clockwise
    | Counter
  [@@deriving sexp, compare, equal, bin_io]
end

(* maps id to card for easy search *)
module Card_registry = struct
  type t = Card.t Int.Map.t [@@deriving sexp, compare, equal, bin_io]

  let of_cards cards = List.fold cards ~init:Int.Map.empty ~f:(fun acc (card : Card.t) -> 
    Map.set acc ~key:card.id ~data:card)
  ;;

  let find t id = 
    match Map.find t id with 
    | Some c -> Ok c
    | None -> Or_error.error_s [%message "Unknown card id" (id : int)]
  ;;
end

(* gamestate *)
type t =
  { players : Player.t list
  ; draw_pile : Card.t List.t (* played pile does not contain top card *)
  ; played_pile : Card.t List.t
  ; top_card : Card.t
  ; current_color : Card.Color.t
  ; direction : Direction.t
  ; turn : int
  ; card_registry : Card_registry.t
  }
[@@deriving sexp, compare, equal, bin_io]

(* creates the initial deck of cards *)
let create_card_deck () : Card.t List.t =
  let next_id = ref 0 in
  let make color effect = 
    let card : Card.t = { color; effect; id = !next_id} in
    Int.incr next_id;
    card 
  in 
  List.concat_map Card.Color.all ~f:(fun color ->
    List.concat_map Card.Effect.all ~f:(fun effect -> 
      let count =
        match color, effect with 
        | NoColor, (Wild | Wild4) -> 4
        | NoColor, _ -> 0
        | _, (Wild | Wild4) -> 0
        | _, Zero -> 1
        | _, _ -> 2
      in
      List.init count ~f:(fun _ -> make color effect)))
;;

(* shuffles deck of cards *)
let shuffle cards =
  let arr = List.to_array cards in
  Array.permute arr;
  Array.to_list arr 
;;

(* grabs a card from draw pile *)
let draw_card t : (Card.t * t) Or_error.t =
  match t.draw_pile with
  | card :: rest -> Ok (card , {t with draw_pile = rest})
  | [] ->
    (match shuffle t.played_pile with
     | [] -> Or_error.error_string "No cards left to reshuffle with..."
     | card :: rest -> Ok (card, { t with draw_pile = rest; played_pile = []}))
;;

(* updates player when they make changes to their hand *)
let update_player t player =
  { t with players = List.map t.players ~f:(fun p -> 
      if Int.equal (Player.get_id p) (Player.get_id player) then player else p)}
;;

(* draws top card in draw pile, reshuffles card if no cards left in draw pile
   return error if no player exists or no playable cards *)
let draw_card_player t player_id : t Or_error.t =
  let%bind player =
    match List.nth t.players player_id with
    | Some p -> Ok p
    | None -> Or_error.error_s [%message "Player ID not found" (player_id : int)]
  in
  let%map card, t = draw_card t in
  update_player t (Player.add_card player (Card.get_id card))
;;

(* updates the the card ontop of played pile *)
let update_top_card t (new_card : Card.t) : t =
  { t with top_card = new_card; current_color = new_card.color }
;;


(* Builds the initial game state: creates and shuffles a full deck, makes one
   player per name (id = position in the list), deals [hand_size] cards to each
   player in order, then flips the top card. The placeholder top_card with
   id = -1 is a stand-in for the empty record field and is always overwritten
   by the final update_top_card. Errors if the deck runs out mid-deal. *)
let create ~player_names ~hand_size : t Or_error.t =
  let deck = create_card_deck () in 
  let players =  List.mapi player_names ~f:(fun id name -> Player.create id name) in
  let t = {
    players
    ; draw_pile = shuffle deck
    ; played_pile = []
    ; top_card = { color = NoColor; effect = Zero; id = -1}
    ; current_color = NoColor
    ; direction = Clockwise
    ; turn = 0
    ; card_registry = Card_registry.of_cards deck
  }
  in
  let%bind t = List.fold_result players ~init:t ~f:(fun t player -> 
    List.fold_result (List.init hand_size ~f:Fn.id) ~init:t ~f:(fun t _ -> 
      draw_card_player t (Player.get_id player)))
    in 
  let%map card, t = draw_card t in
  update_top_card t card  
  ;;