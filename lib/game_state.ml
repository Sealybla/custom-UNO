open! Core
open Or_error.Let_syntax

(* maps id to card for easy search *)
module Card_registry = struct
  type t = Card.t Int.Map.t [@@deriving sexp, compare, equal, bin_io]

  let of_cards cards =
    List.fold cards ~init:Int.Map.empty ~f:(fun acc (card : Card.t) ->
      Map.set acc ~key:card.id ~data:card)
  ;;

  let find t id =
    match Map.find t id with
    | Some c -> Ok c
    | None -> Or_error.error_s [%message "Unknown card id" (id : int)]
  ;;
end

module Effect = struct
  type t =
    | PlayTriggeringCard
    | SetActiveColor of Card.Color.t
    | SetColorFromTriggeringCard
    | SetDeclaredColor
    | AddPendingDraws of int
    | ApplyPendingDraws
    | ExecuteDraw of int
    | DrawForNextPlayer of int
    | DrawUntilPlayable
    | DrawAndDecide
    | ReverseDirection
    | SetStackingValue
    | ClearStackingValue
    | AdvanceTurn
    | CheckWinner
  [@@deriving sexp, compare, equal, bin_io]
end

(* gamestate *)
type t =
  { players : Player.t list
  ; draw_pile : Card.t List.t (* played pile does not contain top card *)
  ; played_pile : Card.t List.t
  ; top_card : Card.t
  ; current_color : Card.Color.t
  ; stacking_value : Card.Value.t option
  ; direction : Direction.t
  ; pending_draws : int
  ; drew_playable : bool
    (* the current player just drew a playable card and may play or pass *)
  ; turn : int
  ; card_registry : Card_registry.t
  ; winner : int Option.t
  }
[@@deriving sexp, compare, equal, bin_io]

let for_testing ~player_hands ~top_card ~draw_pile ~pending_draws ~turn =
  (* player_hands : (string * Card.t list) list *)
  let all_cards =
    (top_card :: draw_pile) @ List.concat_map player_hands ~f:snd
  in
  let players =
    List.mapi player_hands ~f:(fun id (name, cards) ->
      List.fold cards ~init:(Player.create id name) ~f:(fun p c ->
        Player.add_card p (Card.get_id c)))
  in
  { players
  ; draw_pile
  ; played_pile = []
  ; top_card
  ; current_color = Card.get_color top_card
  ; stacking_value = None
  ; direction = Direction.Clockwise
  ; pending_draws
  ; drew_playable = false
  ; turn
  ; card_registry = Card_registry.of_cards all_cards
  ; winner = None
  }
;;

(* creates the initial deck of cards *)
let create_card_deck () : Card.t List.t =
  let next_id = ref 0 in
  let make color value =
    let card : Card.t = { color; value; id = !next_id } in
    Int.incr next_id;
    card
  in
  List.concat_map Card.Color.all ~f:(fun color ->
    List.concat_map Card.Value.all ~f:(fun value ->
      let count =
        match color, value with
        | NoColor, (Wild | Wild4) -> 4
        | NoColor, _ -> 0
        | _, (Wild | Wild4) -> 0
        | _, Zero -> 1
        | _, _ -> 2
      in
      List.init count ~f:(fun _ -> make color value)))
;;

(* shuffles deck of cards *)
let shuffle ?random_state cards =
  let arr = List.to_array cards in
  Array.permute ?random_state arr;
  Array.to_list arr
;;

(* grabs a card from draw pile *)
let draw_card t : (Card.t * t) Or_error.t =
  match t.draw_pile with
  | card :: rest -> Ok (card, { t with draw_pile = rest })
  | [] ->
    (match shuffle t.played_pile with
     | [] -> Or_error.error_string "No cards left to reshuffle with..."
     | card :: rest ->
       Ok (card, { t with draw_pile = rest; played_pile = [] }))
;;

(* updates player when they make changes to their hand *)
let update_player t player =
  { t with
    players =
      List.map t.players ~f:(fun p ->
        if Int.equal (Player.get_id p) (Player.get_id player)
        then player
        else p)
  }
;;

(* draws top card in draw pile, reshuffles card if no cards left in draw pile
   return error if no player exists or no playable cards *)
let draw_card_player t player_id : t Or_error.t =
  let%bind player =
    match List.nth t.players player_id with
    | Some p -> Ok p
    | None ->
      Or_error.error_s [%message "Player ID not found" (player_id : int)]
  in
  let%map card, t = draw_card t in
  update_player t (Player.add_card player (Card.get_id card))
;;

(* updates the the card ontop of played pile *)
let update_top_card t (new_card : Card.t) : t =
  { t with top_card = new_card; current_color = new_card.color }
;;

let card_of_event (event : Event.t) =
  match event with
  | CardPlayed { card; _ } -> Ok card
  | _ ->
    Or_error.error_s
      [%message "effect needs a played card" (event : Event.t)]
;;

let player_of_event (event : Event.t) =
  match event with
  | CardPlayed { player; _ } -> Ok player
  | DrawRequested { player } -> Ok player
  | PassRequested { player } -> Ok player
;;

(* Builds the initial game state: creates and shuffles a full deck, makes one
   player per name (id = position in the list), deals [hand_size] cards to
   each player in order, then flips the top card. The placeholder top_card
   with id = -1 is a stand-in for the empty record field and is always
   overwritten by the final update_top_card. Errors if the deck runs out
   mid-deal. *)
let create ?random_state ~player_names ~hand_size () : t Or_error.t =
  let deck = create_card_deck () in
  let players =
    List.mapi player_names ~f:(fun id name -> Player.create id name)
  in
  let t =
    { players
    ; draw_pile = shuffle ?random_state deck
    ; played_pile = []
    ; top_card = { color = NoColor; value = Zero; id = -1 }
    ; current_color = NoColor
    ; direction = Direction.Clockwise
    ; stacking_value = None
    ; pending_draws = 0
    ; drew_playable = false
    ; turn = 0
    ; card_registry = Card_registry.of_cards deck
    ; winner = None
    }
  in
  let%bind t =
    List.fold_result players ~init:t ~f:(fun t player ->
      List.fold_result (List.init hand_size ~f:Fn.id) ~init:t ~f:(fun t _ ->
        draw_card_player t (Player.get_id player)))
  in
  let%map card, t = draw_card t in
  update_top_card t card
;;

(* passing the turn also forgets the drawn-card decision *)
let advance_turn t =
  let num_players = List.length t.players in
  let dir = match t.direction with Clockwise -> 1 | Counter -> -1 in
  (* add num_players again to account for neg mod *)
  let next_turn = (t.turn + dir + num_players) % num_players in
  { t with turn = next_turn; drew_playable = false }
;;

(* apply an effect to game state t *)
let apply_effect t ~(event : Event.t) (eff : Effect.t) : t Or_error.t =
  match eff with
  | PlayTriggeringCard ->
    let%bind player = player_of_event event in
    let%bind card = card_of_event event in
    let%map updated = Player.remove_card player (Card.get_id card) in
    let t = update_player t updated in
    { t with top_card = card; played_pile = t.top_card :: t.played_pile }
  | SetActiveColor color -> Ok { t with current_color = color }
  | SetColorFromTriggeringCard ->
    let%map card = card_of_event event in
    { t with current_color = Card.get_color card }
  | SetDeclaredColor ->
    (match event with
     | CardPlayed { declared_color = Some color; _ } ->
       Ok { t with current_color = color }
     | CardPlayed { declared_color = None; _ } ->
       Or_error.error_string "Wild requires a declared color"
     | _ ->
       Or_error.error_s
         [%message "SetDeclaredColor needs a card play" (event : Event.t)])
  | AddPendingDraws n -> Ok { t with pending_draws = t.pending_draws + n }
  | ApplyPendingDraws ->
    let%bind player = player_of_event event in
    let n = t.pending_draws in
    let%map t =
      List.fold_result (List.init n ~f:Fn.id) ~init:t ~f:(fun s _ ->
        draw_card_player s (Player.get_id player))
    in
    { t with pending_draws = 0 }
  | ExecuteDraw n ->
    let%bind player = player_of_event event in
    List.fold_result (List.init n ~f:Fn.id) ~init:t ~f:(fun s _ ->
      draw_card_player s (Player.get_id player))
  | DrawForNextPlayer count ->
    (* the target is the NEXT player in turn order (respecting direction),
       not the actor - and whose turn it is does not change *)
    let dir = if Direction.equal t.direction Clockwise then 1 else -1 in
    let num_players = List.length t.players in
    let player_id = (t.turn + dir + num_players) % num_players in
    List.fold_result (List.init count ~f:Fn.id) ~init:t ~f:(fun s _ ->
      draw_card_player s player_id)
  | DrawUntilPlayable ->
    let%bind player = player_of_event event in
    let player_id = Player.get_id player in
    let rec loop t drawn =
      if drawn >= 108
      then Ok t
      else (
        let%bind t = draw_card_player t player_id in
        let hand_ids = Player.get_hand (List.nth_exn t.players player_id) in
        match hand_ids with
        | [] -> Ok t
        | newest_id :: _ ->
          let%bind card = Card_registry.find t.card_registry newest_id in
          if Game_rules.is_valid_play
               ~top_card:t.top_card
               ~played_card:card
               ~current_color:t.current_color
          then Ok { t with drew_playable = true }
          else loop t (drawn + 1))
    in
    loop t 0
  | DrawAndDecide ->
    (* draw one card; if it is playable the turn stays open so the player
       can choose to play it or pass, otherwise the turn passes *)
    let%bind player = player_of_event event in
    let player_id = Player.get_id player in
    let%bind t = draw_card_player t player_id in
    let%bind drawn_player =
      match List.nth t.players player_id with
      | Some p -> Ok p
      | None ->
        Or_error.error_s [%message "Player ID not found" (player_id : int)]
    in
    (match Player.get_hand drawn_player with
     | [] -> Ok (advance_turn t)
     | newest_id :: _ ->
       let%map card = Card_registry.find t.card_registry newest_id in
       if Game_rules.is_valid_play
            ~top_card:t.top_card
            ~played_card:card
            ~current_color:t.current_color
       then { t with drew_playable = true }
       else advance_turn t)
  | ReverseDirection ->
    let next_dir =
      match t.direction with
      | Clockwise -> Direction.Counter
      | Counter -> Clockwise
    in
    Ok { t with direction = next_dir }
  | SetStackingValue ->
    let%map card = card_of_event event in
    { t with stacking_value = Some (Card.get_value card) }
  | ClearStackingValue -> Ok { t with stacking_value = None }
  | AdvanceTurn -> Ok (advance_turn t)
  | CheckWinner ->
    let%map player = player_of_event event in
    let id = Player.get_id player in
    let current_player =
      List.find t.players ~f:(fun p -> Int.equal (Player.get_id p) id)
    in
    let winner =
      match current_player with
      | Some p when List.is_empty (Player.get_hand p) -> Some id
      | _ -> None
    in
    { t with winner }
;;
