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

(* When does emptying your hand end the GAME, as opposed to just taking you
   out of it? Classic Uno stops at the first player out; the other two modes
   keep the remaining players going for the lower places. *)
module Finish = struct
  type t =
    | First_out (* the first empty hand ends the game *)
    | After of int (* stop once this many players are out *)
    | Last_standing (* play on until only one player still holds cards *)
  [@@deriving sexp, compare, equal, bin_io]

  (* how many players must go out before the game is over. Never more than
     one short of the table: nobody can take the last place from themselves,
     so "until 5 finish" at a table of 3 would otherwise never end. *)
  let needed t ~num_players =
    let all_but_one = Int.max 1 (num_players - 1) in
    match t with
    | First_out -> 1
    | Last_standing -> all_but_one
    | After n -> Int.min (Int.max 1 n) all_but_one
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
    (* records an emptied hand as out, and ends the game once the finish
       mode says enough players have gone *)
    | CheckWinner of Finish.t
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
       with [target_needed_swap] when no target was declared *)
    | SwapHandsWithChosen
    (* every hand moves one seat in the play direction (seven-zero's 0) *)
    | RotateHands
    (* every player except the actor draws (chaos house rules) *)
    | AllOthersDraw of int
    (* the player the actor aimed the card at draws (targeted +4 rules);
       rejects with [target_needed_draw] when no target was declared. NO winner
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
  ; finished : int List.t
    (* players who have emptied their hand, in the order they did it: first
       place first. They keep their seat but are skipped forever after. *)
  ; card_registry : Card_registry.t
  ; winner : int Option.t
    (* set only when the GAME is over; it is whoever came first. With a
       multi-winner finish mode the full podium is [finished]. *)
  }
[@@deriving sexp, compare, equal, bin_io]

(* NoColor means no color is in force yet. The only way a game reaches that
   state is the flipped starting card being a wild, which nobody chose a
   color for - so the opening player may lead with whatever they like. *)
let matches_color t ~(played_card : Card.t) =
  match t.current_color with
  | Card.Color.NoColor -> true
  | color -> Card.Color.equal played_card.color color
;;

let is_valid_play t ~(played_card : Card.t) =
  match played_card.value with
  | Card.Value.Wild | Card.Value.Wild4 -> true
  | _ ->
    matches_color t ~played_card
    || Card.Value.equal played_card.value t.top_card.Card.value
;;

(* first playable card in hand, or None if nothing is playable; bot logic *)
let first_playable_card t ~hand =
  List.find hand ~f:(fun card -> is_valid_play t ~played_card:card)
;;

let for_testing
  ?current_color
  ?stacking_value
  ?direction
  ?drew_playable
  ?uno_vulnerable
  ~player_hands
  ~top_card
  ~draw_pile
  ~pending_draws
  ~turn
  ()
  =
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
  ; current_color =
      Option.value current_color ~default:(Card.get_color top_card)
  ; stacking_value
  ; direction = Option.value direction ~default:Direction.Clockwise
  ; pending_draws
  ; drew_playable = Option.value drew_playable ~default:false
  ; turns_advanced = 0
  ; turn
  ; uno_vulnerable
  ; finished = []
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

(* grabs a card from the draw pile, reshuffling the played pile into it
   when it runs out; None when both piles are empty *)
let draw_card_opt t : (Card.t * t) option =
  match t.draw_pile with
  | card :: rest -> Some (card, { t with draw_pile = rest })
  | [] ->
    (match shuffle t.played_pile with
     | [] -> None
     | card :: rest ->
       Some (card, { t with draw_pile = rest; played_pile = [] }))
;;

(* strict variant for the opening flip, where running out is a real error *)
let draw_card t : (Card.t * t) Or_error.t =
  match draw_card_opt t with
  | Some result -> Ok result
  | None -> Or_error.error_string "No cards left to reshuffle with..."
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

(* one card into [player_id]'s hand; false when both piles are dry. That is
   not an error: at the tail of a long game a draw can simply yield nothing
   and play continues, the same as running the physical deck out *)
let try_draw_card_player t player_id : (t * bool) Or_error.t =
  let%map player =
    match List.nth t.players player_id with
    | Some p -> Ok p
    | None ->
      Or_error.error_s [%message "Player ID not found" (player_id : int)]
  in
  match draw_card_opt t with
  | None -> t, false
  | Some (card, t) ->
    update_player t (Player.add_card player (Card.get_id card)), true
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

(* up to [n] cards off the top of the pile into one player's hand, stopping
   quietly when both piles run dry - a penalty is worth whatever is left *)
let draw_n t player_id n =
  let rec go t remaining =
    if remaining <= 0
    then Ok t
    else (
      let%bind t, drew = try_draw_card_player t player_id in
      if drew then go t (remaining - 1) else Ok t)
  in
  go t n
;;

(* the engine's playability probe matches these exact strings to sort
   needs-a-target cards from illegal ones - and swaps from aimed draws, so
   the UI can word its picker by what the card does. Keep them distinct. *)
let target_needed_swap = "Choose another player to swap hands with"
let target_needed_draw = "Choose another player to aim the draw at"

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
   overwritten by the final update_top_card. Checked up front rather than
   erroring mid-deal, because draw_n draws best-effort and would otherwise
   silently deal short, unequal hands. *)
let create ?random_state ~player_names ~hand_size () : t Or_error.t =
  let deck = create_card_deck () in
  let%bind () =
    let needed = (hand_size * List.length player_names) + 1 in
    if needed > List.length deck
    then
      Or_error.error_s
        [%message
          "Not enough cards in the deck to deal that hand size"
            (hand_size : int)
            ~players:(List.length player_names : int)
            ~deck:(List.length deck : int)]
    else Ok ()
  in
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
    ; finished = []
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

let is_finished t player_id = List.mem t.finished player_id ~equal:Int.equal

(* the next seat in play direction that has not finished, or [from] itself
   when everybody else is out. Finished players keep their seat but are
   invisible to everything that walks the table - the turn, +2/+4 targets,
   swap neighbors - or penalties would land in dead hands while the live
   victim walks free. [tried] bounds the walk: if every seat is finished
   there is no live seat to land on and we would otherwise loop forever. *)
let next_live_seat t ~from =
  let num_players = List.length t.players in
  let dir = match t.direction with Clockwise -> 1 | Counter -> -1 in
  (* add num_players again to account for neg mod *)
  let step idx = (idx + dir + num_players) % num_players in
  let rec go idx tried =
    if tried >= num_players || not (is_finished t idx)
    then idx
    else go (step idx) (tried + 1)
  in
  go (step from) 1
;;

(* passing the turn also forgets the drawn-card decision *)
let advance_turn t =
  { t with
    turn = next_live_seat t ~from:t.turn
  ; drew_playable = false
  ; turns_advanced = t.turns_advanced + 1
  }
;;

(* apply an effect to game state t *)
(* [card_playable] is how the draw effects judge the card they just drew.
   Rule_engine passes a full ruleset simulation so "playable" agrees with
   the UI highlights under custom rules; the default is official-rules
   matching, for callers with no ruleset in hand (tests). *)
let apply_effect ?card_playable t ~(event : Event.t) (eff : Effect.t)
  : t Or_error.t
  =
  let card_playable =
    match card_playable with
    | Some f -> f
    | None -> fun t ~player_id:_ ~played_card -> is_valid_play t ~played_card
  in
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
    (* the target is the next LIVE player in turn order (respecting
       direction), not the actor - and whose turn it is does not change *)
    draw_n t (next_live_seat t ~from:t.turn) count
  | DrawUntilPlayable ->
    (* one card per draw click, the turn staying put either way; a playable
       draw sets drew_playable for rules that condition on it. A dry deck
       turns the click into a pass - the variant has no pass rule, so the
       seat would otherwise be left with no legal move *)
    let%bind player = player_of_event event in
    let player_id = Player.get_id player in
    let%bind t, drew = try_draw_card_player t player_id in
    if not drew
    then Ok (advance_turn t)
    else (
      match Player.get_hand (List.nth_exn t.players player_id) with
      | [] -> Ok t
      | newest_id :: _ ->
        let%map card = Card_registry.find t.card_registry newest_id in
        if card_playable t ~player_id ~played_card:card
        then { t with drew_playable = true }
        else t)
  | DrawAndDecide ->
    (* draw one card; if it is playable the turn stays open so the player
       can choose to play it or pass, otherwise the turn passes. A dry deck
       draws nothing and the turn passes *)
    let%bind player = player_of_event event in
    let player_id = Player.get_id player in
    let%bind t, drew = try_draw_card_player t player_id in
    if not drew
    then Ok (advance_turn t)
    else (
      match Player.get_hand (List.nth_exn t.players player_id) with
      | [] -> Ok (advance_turn t)
      | newest_id :: _ ->
        let%map card = Card_registry.find t.card_registry newest_id in
        if card_playable t ~player_id ~played_card:card
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
    let target = next_live_seat t ~from:actor in
    (* [is_finished actor], not [t.winner]: in a multi-winner game a mid-game
       finish leaves winner unset, but the finisher must still walk away
       without trading their empty hand for a live one *)
    if is_finished t actor || target = actor
    then t (* going out on the card finishes outright - no swap after that *)
    else swap_hands t ~a:actor ~b:target
  | SwapHandsWithChosen ->
    let%bind player = player_of_event event in
    if is_finished t (Player.get_id player)
    then
      (* checked before demanding a target: a finishing play needs none *)
      Ok t
    else (
      match event with
      | Event.CardPlayed { swap_with = Some target; _ } ->
        if is_finished t (Player.get_id target)
        then
          Or_error.error_string
            "That player has already finished - pick someone still playing"
        else
          Ok (swap_hands t ~a:(Player.get_id player) ~b:(Player.get_id target))
      | Event.CardPlayed { swap_with = None; _ } ->
        Or_error.error_string target_needed_swap
      | _ ->
        Or_error.error_string
          "'swap hands with chosen player' only makes sense on a card play")
  | RotateHands ->
    let%map player = player_of_event event in
    if is_finished t (Player.get_id player)
    then t (* going out on the card finishes outright - hands stay put *)
    else (
      (* rotation runs over LIVE seats only: finished seats keep their
         (empty) hands, or a live hand would rotate into a dead seat and
         an empty one back into play *)
      let live =
        List.filter_map t.players ~f:(fun p ->
          let id = Player.get_id p in
          if is_finished t id then None else Some id)
      in
      let k = List.length live in
      if k <= 1
      then t
      else (
        let dir = if Direction.equal t.direction Clockwise then 1 else -1 in
        let hands = List.map t.players ~f:Player.get_hand in
        let players =
          (* your hand goes to the live seat ahead of you, so the hand you
             receive comes from the live seat behind you (in direction) *)
          List.mapi t.players ~f:(fun i p ->
            match List.findi live ~f:(fun _ id -> Int.equal id i) with
            | None -> p
            | Some (li, _) ->
              let from_seat = List.nth_exn live ((li - dir + k) % k) in
              Player.with_hand p (List.nth_exn hands from_seat))
        in
        { t with players }))
  | AllOthersDraw count ->
    let%bind player = player_of_event event in
    let actor = Player.get_id player in
    (* finished seats are out of the game; feeding them cards would drain
       the deck into hands that can never play again *)
    List.fold_result t.players ~init:t ~f:(fun acc p ->
      let id = Player.get_id p in
      if id = actor || is_finished acc id
      then Ok acc
      else draw_n acc id count)
  | ChosenPlayerDraws n ->
    (match event with
     | Event.CardPlayed { swap_with = Some target; _ } ->
       if is_finished t (Player.get_id target)
       then
         Or_error.error_string
           "That player has already finished - pick someone still playing"
       else draw_n t (Player.get_id target) n
     | Event.CardPlayed { swap_with = None; _ } ->
       Or_error.error_string target_needed_draw
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
  | CheckWinner finish ->
    let%map player = player_of_event event in
    let actor = Player.get_id player in
    let emptied id =
      match
        List.find t.players ~f:(fun p -> Int.equal (Player.get_id p) id)
      with
      | Some p -> List.is_empty (Player.get_hand p)
      | None -> false
    in
    (* order matters: [finished] is the podium, first place first. Only the
       actor is examined: the hand-moving effects guarantee no OTHER live
       player can be emptied (a finished actor never swaps or rotates, and
       trades between live players exchange non-empty hands), and tests
       legitimately build mid-game states with empty fixture hands that a
       whole-table sweep would wrongly send to the podium *)
    let finished =
      if emptied actor && not (is_finished t actor)
      then t.finished @ [ actor ]
      else t.finished
    in
    let needed =
      Finish.needed finish ~num_players:(List.length t.players)
    in
    let winner =
      if List.length finished >= needed then List.hd finished else None
    in
    { t with finished; winner }
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
