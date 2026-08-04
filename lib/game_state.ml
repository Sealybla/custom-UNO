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
    (* hand the turn to whoever acted, wherever they were sitting. Combined
       with a rule that omits "your turn" this is how playing out of turn
       works: everyone between the seat whose turn it was and the player who
       jumped loses their go. *)
    | JumpToActor
    | CheckWinner
    (* the caller is safe: shuts their own catch window *)
    | MarkUnoCalled
    (* the caller pressed UNO with nothing to claim *)
    | PenalizeUnoCaller of int
    (* the caller caught somebody sitting on one card *)
    | PenalizeUnoTarget of int
    (* the actor trades entire hands with the next player in play
       direction (seven-zero's 7). Runs after PlayTriggeringCard, so the
       played card is already gone from the hand being traded away. *)
    | SwapHandsWithNext
    (* like SwapHandsWithNext but with the player the actor named when
       playing the card (the authentic seven-zero 7); rejects the play
       with [target_needed] when no target was declared *)
    | SwapHandsWithChosen
    (* every hand moves one seat in the play direction (seven-zero's 0) *)
    | RotateHands
    (* every player except the actor draws (chaos house rules) *)
    | AllOthersDraw of int
    (* the player the actor aimed the card at draws (targeted +4 rules);
       rejects with [target_needed] when no target was declared. NO winner
       guard: like the built-in +2/+4, a winning final card still delivers
       its draws. *)
    | ChosenPlayerDraws of int
    (* fail the whole action with this message. A rule that wins the click
       and rejects it makes that move ILLEGAL - the playability simulation
       sees the error, so the UI won't even light the card up. This is how
       blocking rules work ("no going out on an action card"). *)
    | Reject of string
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
  ; turns_advanced : int
    (* monotonic count of turn advances; diffing it across one action tells
       the server how many seats the turn moved (2+ means someone was
       skipped), which drives the "you got skipped" notifications *)
  ; turn : int
  ; uno_vulnerable : int Option.t
    (* the one player who can currently be caught for not calling UNO: they
       played down to a single card and nobody has taken a gameplay turn
       since. At most one player can be in this position at a time, because
       only the actor's own hand can shrink on their move. *)
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
  ; turns_advanced = 0
  ; turn
  ; uno_vulnerable = None
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
  | UnoCalled { player } -> Ok player
;;

(* a gameplay move consumes a turn; an UNO press does not. Only the former
   closes an opponent's catch window. *)
let is_gameplay_event (event : Event.t) =
  match event with
  | CardPlayed _ | DrawRequested _ | PassRequested _ -> true
  | UnoCalled _ -> false
;;

let hand_size t player_id =
  match List.nth t.players player_id with
  | Some p -> List.length (Player.get_hand p)
  | None -> 0
;;

(* [n] cards off the top of the pile into one player's hand *)
let draw_n t player_id n =
  List.fold_result (List.init n ~f:Fn.id) ~init:t ~f:(fun s _ ->
    draw_card_player s player_id)
;;

let target_needed = "Choose another player to aim this card at"

(* trade two players' entire hands. No catch-window bookkeeping here:
   update_uno_window recomputes it from the actor's final hand after every
   action, so swapping into a one-card hand correctly leaves the actor
   catchable. *)
let swap_hands t ~a ~b =
  let hand_of id = Player.get_hand (List.nth_exn t.players id) in
  let a_hand = hand_of a
  and b_hand = hand_of b in
  let players =
    List.map t.players ~f:(fun p ->
      let id = Player.get_id p in
      if id = a
      then Player.with_hand p b_hand
      else if id = b
      then Player.with_hand p a_hand
      else p)
  in
  { t with players }
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
    ; turns_advanced = 0
    ; turn = 0
    ; uno_vulnerable = None
    ; card_registry = Card_registry.of_cards deck
    ; winner = None
    }
  in
  let%bind t =
    List.fold_result players ~init:t ~f:(fun t player ->
      draw_n t (Player.get_id player) hand_size)
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
  { t with
    turn = next_turn
  ; drew_playable = false
  ; turns_advanced = t.turns_advanced + 1
  }
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
    let%map t = draw_n t (Player.get_id player) t.pending_draws in
    { t with pending_draws = 0 }
  | ExecuteDraw n ->
    let%bind player = player_of_event event in
    draw_n t (Player.get_id player) n
  | DrawForNextPlayer count ->
    (* the target is the NEXT player in turn order (respecting direction),
       not the actor - and whose turn it is does not change *)
    let dir = if Direction.equal t.direction Clockwise then 1 else -1 in
    let num_players = List.length t.players in
    let player_id = (t.turn + dir + num_players) % num_players in
    draw_n t player_id count
  | DrawUntilPlayable ->
    (* one card per draw click, the turn staying put either way; a playable
       draw sets drew_playable for rules that condition on it *)
    let%bind player = player_of_event event in
    let player_id = Player.get_id player in
    let%bind t = draw_card_player t player_id in
    (match Player.get_hand (List.nth_exn t.players player_id) with
     | [] -> Ok t
     | newest_id :: _ ->
       let%map card = Card_registry.find t.card_registry newest_id in
       if Game_rules.is_valid_play
            ~top_card:t.top_card
            ~played_card:card
            ~current_color:t.current_color
       then { t with drew_playable = true }
       else t)
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
    let t = { t with direction = next_dir } in
    (* official 2-player rule: a reverse acts like a skip. Flipping the
       direction alone would make it a no-op, so eat one extra turn here;
       the reverse rule's own "advance turn" then lands back on the player
       who played it. *)
    if Int.equal (List.length t.players) 2 then Ok (advance_turn t) else Ok t
  | SetStackingValue ->
    let%map card = card_of_event event in
    { t with stacking_value = Some (Card.get_value card) }
  | ClearStackingValue -> Ok { t with stacking_value = None }
  | MarkUnoCalled ->
    (* only clears the caller's own window. Calling while safe (or while
       holding a full hand) is a harmless no-op here; the rule that lets a
       bare press through is what decides whether it costs cards. *)
    let%map player = player_of_event event in
    let id = Player.get_id player in
    if Option.exists t.uno_vulnerable ~f:(Int.equal id)
    then { t with uno_vulnerable = None }
    else t
  | PenalizeUnoCaller n ->
    let%bind player = player_of_event event in
    draw_n t (Player.get_id player) n
  | PenalizeUnoTarget n ->
    (match t.uno_vulnerable with
     | None ->
       Or_error.error_string "No player is open to an UNO catch right now"
     | Some victim ->
       (* the catch is spent whether or not it stung *)
       let%map t = draw_n t victim n in
       { t with uno_vulnerable = None })
  | SwapHandsWithNext ->
    let%map player = player_of_event event in
    let actor = Player.get_id player in
    let n = List.length t.players in
    let dir = if Direction.equal t.direction Clockwise then 1 else -1 in
    let target = (actor + dir + n) % n in
    if Option.is_some t.winner || target = actor
    then t (* going out on the card wins outright - no swap after a win *)
    else swap_hands t ~a:actor ~b:target
  | SwapHandsWithChosen ->
    let%bind player = player_of_event event in
    if Option.is_some t.winner
    then Ok t (* checked before demanding a target: a winning play needs none *)
    else (
      match event with
      | Event.CardPlayed { swap_with = Some target; _ } ->
        Ok (swap_hands t ~a:(Player.get_id player) ~b:(Player.get_id target))
      | Event.CardPlayed { swap_with = None; _ } ->
        Or_error.error_string target_needed
      | _ ->
        Or_error.error_string
          "'swap hands with chosen player' only makes sense on a card play")
  | RotateHands ->
    if Option.is_some t.winner
    then Ok t (* going out on the card wins outright - hands stay put *)
    else (
      let n = List.length t.players in
      let dir = if Direction.equal t.direction Clockwise then 1 else -1 in
      let hands = List.map t.players ~f:Player.get_hand in
      let players =
        (* your hand goes to the seat ahead of you, so the hand you receive
           comes from the seat behind you (in play direction) *)
        List.mapi t.players ~f:(fun i p ->
          Player.with_hand p (List.nth_exn hands ((i - dir + n) % n)))
      in
      Ok { t with players })
  | AllOthersDraw count ->
    let%bind player = player_of_event event in
    let actor = Player.get_id player in
    List.fold_result t.players ~init:t ~f:(fun acc p ->
      let id = Player.get_id p in
      if id = actor then Ok acc else draw_n acc id count)
  | ChosenPlayerDraws n ->
    (match event with
     | Event.CardPlayed { swap_with = Some target; _ } ->
       draw_n t (Player.get_id target) n
     | Event.CardPlayed { swap_with = None; _ } ->
       Or_error.error_string target_needed
     | _ ->
       Or_error.error_string
         "'chosen player draws' only makes sense on a card play")
  | Reject message ->
    (* the error unwinds the whole action, so any effects before this one
       are discarded too - the state never changes on a rejected move *)
    Or_error.error_string message
  | JumpToActor ->
    let%map player = player_of_event event in
    (* the interrupted player may have been mid-decision on a drawn card;
       jumping in cancels that offer *)
    { t with turn = Player.get_id player; drew_playable = false }
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

(* Bookkeeping for the UNO catch window, run by Rule_engine.apply_action once
   per action, after the rules have had their say. Deliberately not an Effect:
   a player editing the rules in the browser must not be able to rewrite the
   window out from under everyone else.

   [actor_id] is whoever took the action and [event] is what they did.
   Returns the state with [uno_vulnerable] brought up to date. *)
let update_uno_window t ~(actor_id : int) ~(event : Event.t) : t =
  if not (is_gameplay_event event)
  then
    (* an UNO press is not a turn. The effects own the window here:
       MarkUnoCalled shuts it, PenalizeUnoTarget spends it. Recomputing
       would immediately re-open the window on the caller and undo the very
       call they just made. *)
    t
  else (
    (* One assignment covers both halves of "vulnerable until the next
       player acts". Only the actor's own hand can shrink on their move, so
       any window that was standing belonged to someone whose turn has now
       been followed by a gameplay action - it closes no matter whose it
       was - and the only player who can be newly catchable is the actor.

       Falls out of this for free: playing your last card wins rather than
       leaving you catchable (hand 0), drawing back up to two closes your
       own window, and acting twice in one turn mid-stack keeps it open,
       since nobody else has acted in between. *)
    let vulnerable =
      if Int.equal (hand_size t actor_id) 1 then Some actor_id else None
    in
    { t with uno_vulnerable = vulnerable })
;;

(* see the .mli. [played] is removed from every before-hand rather than just
   the actor's: card ids are unique, so it is a no-op everywhere else. *)
let hand_moves ~(before : t) ~(after : t) ~(played : int option)
  : (int * int) list
  =
  let hand_set p = Int.Set.of_list (Player.get_hand p) in
  let befores =
    List.map before.players ~f:(fun p ->
      let s = hand_set p in
      match played with
      | Some c -> Set.remove s c
      | None -> s)
  in
  List.filter_mapi after.players ~f:(fun i receiver ->
    let after_hand = hand_set receiver in
    match List.nth befores i with
    | None -> None
    | Some own_before ->
      if Set.is_empty after_hand || Set.equal after_hand own_before
      then None
      else
        List.find_mapi befores ~f:(fun j before_j ->
          if j = i || Set.is_empty before_j
          then None
          else if Set.equal after_hand before_j
          then Some (j, i)
          else None))
;;
