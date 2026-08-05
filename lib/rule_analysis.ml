open! Core

module Relation = struct
  type t =
    | Disjoint
    | Equivalent
    | Left_subsumes
    | Right_subsumes
    | Overlap
    | Unknown
  [@@deriving sexp, compare, equal]
end

(* How many (state, event) pairs we are willing to build. Reached only by
   conditions that read most of the state at once; the rules people actually
   write touch three or four dimensions and land in the low thousands. *)
let world_budget = 120_000
let state_budget = 20_000

(* ------------------------------------------------------------------ *)
(* what a condition reads                                              *)
(* ------------------------------------------------------------------ *)

(* Which parts of the world a condition can distinguish. Anything not listed
   here is held at a fixed default, which is what keeps the enumeration
   small: a condition that only asks about colours does not pay for the
   draw-pile dimension. *)
type profile =
  { mutable played : bool (* the card being played *)
  ; mutable top : bool (* the card showing on the pile *)
  ; mutable active_color : bool
  ; mutable turn : bool
  ; mutable hand : bool (* the actor's own hand size *)
  ; mutable opp_hand : bool
  ; mutable pending : bool
  ; mutable stack : bool
  ; mutable drew : bool
  ; mutable direction : bool
  ; mutable draw_pile : bool
  ; mutable vulnerable : bool
  ; (* thresholds and names the conditions mention, so the domains can be
       widened to tell them apart *)
    mutable hand_ns : Int.Set.t
  ; mutable opp_ns : Int.Set.t
  ; mutable pending_ns : Int.Set.t
  ; mutable pile_ns : Int.Set.t
  ; mutable colors : Card.Color.t list
  ; mutable numbers : int list
  }

let empty_profile () =
  { played = false
  ; top = false
  ; active_color = false
  ; turn = false
  ; hand = false
  ; opp_hand = false
  ; pending = false
  ; stack = false
  ; drew = false
  ; direction = false
  ; draw_pile = false
  ; vulnerable = false
  ; hand_ns = Int.Set.empty
  ; opp_ns = Int.Set.empty
  ; pending_ns = Int.Set.empty
  ; pile_ns = Int.Set.empty
  ; colors = []
  ; numbers = []
  }
;;

let rec scan (p : profile) (cond : Rule.Condition.t) =
  match cond with
  | And (a, b) | Or (a, b) ->
    scan p a;
    scan p b
  | Not c -> scan p c
  | Always -> ()
  (* the played card, sometimes against the pile or the active colour *)
  | MatchesTopColor ->
    p.played <- true;
    p.active_color <- true
  | MatchesTopValue | MatchesTopExactly ->
    p.played <- true;
    p.top <- true
  | IsWildCard | IsSkip | IsReverse | IsPlusTwo | IsPlusFour | IsActionCard
  | IsNumberCard -> p.played <- true
  | IsNumber n ->
    p.played <- true;
    p.numbers <- n :: p.numbers
  | IsCardColor c ->
    p.played <- true;
    p.colors <- c :: p.colors
  | ContinuesStack ->
    p.played <- true;
    p.stack <- true
  (* the pile *)
  | TopCardIsAction -> p.top <- true
  | TopCardIsNumber n ->
    p.top <- true;
    p.numbers <- n :: p.numbers
  | ActiveColorIs c ->
    p.active_color <- true;
    p.colors <- c :: p.colors
  (* the actor *)
  | IsPlayerTurn -> p.turn <- true
  | HandSizeGreaterThan n | HandSizeEquals n ->
    p.hand <- true;
    p.hand_ns <- Set.add p.hand_ns n
  | CallerHasUno ->
    (* "the caller holds exactly one card" - the same dimension, with an
       implicit threshold of 1 *)
    p.hand <- true;
    p.hand_ns <- Set.add p.hand_ns 1
  (* everyone else *)
  | AnyOpponentHandEquals n | AnyOpponentHandGreaterThan n ->
    p.opp_hand <- true;
    p.opp_ns <- Set.add p.opp_ns n
  | SomeoneElseHasUno -> p.vulnerable <- true
  (* the table *)
  | PendingDrawsGreaterThan n ->
    p.pending <- true;
    p.pending_ns <- Set.add p.pending_ns n
  | DrawPileLessThan n ->
    p.draw_pile <- true;
    p.pile_ns <- Set.add p.pile_ns n
  | StackIsOpen -> p.stack <- true
  | DrewPlayableCard -> p.drew <- true
  | DirectionIsClockwise -> p.direction <- true
  (* the kind of action; the event dimension always varies, so nothing to
     record - listed so a new atom cannot be forgotten here *)
  | IsDrawAction | IsPassAction | IsUnoCall -> ()
;;

let profile_of conditions =
  let p = empty_profile () in
  List.iter conditions ~f:(scan p);
  p
;;

(* ------------------------------------------------------------------ *)
(* the abstract domains                                                *)
(* ------------------------------------------------------------------ *)

let card ~color ~value ~id = { Card.color; value; id }

(* Both sides of every threshold, plus zero. "> n" and "= n" are told apart
   by n and n+1; nothing else can distinguish them, so nothing else is
   worth enumerating. *)
let numeric_domain ns =
  let vs = Set.fold ns ~init:[ 0 ] ~f:(fun acc n -> n :: (n + 1) :: acc) in
  List.dedup_and_sort (List.filter vs ~f:(fun n -> n >= 0)) ~compare:Int.compare
;;

(* Two colours so "same colour" and "different colour" are both reachable,
   a number card, one of each action shape, and both wilds. Extended with
   whatever the conditions name so `card is green` is never judged
   impossible just because green was missing. *)
let card_domain (p : profile) =
  let base =
    [ Card.Color.Red, Card.Value.Zero
    ; Red, One
    ; Red, Skip
    ; Red, Reverse
    ; Red, Plus
    ; Blue, Zero
    ; Blue, Skip
    ; NoColor, Wild
    ; NoColor, Wild4
    ]
  in
  let named_colors =
    List.concat_map p.colors ~f:(fun c ->
      match c with
      | Card.Color.NoColor -> []
      | c -> [ c, Card.Value.Zero; c, Skip ])
  in
  (* one colour per named number is enough: the base set already carries a
     same-value/different-colour pair (red and blue zero) for reasoning about
     colour, and the number itself appears in both the played and the top
     domain, so value and exact matching are both reachable. Adding a second
     colour per number would roughly double a domain whose cost is
     quadratic - it feeds both the pile dimension and the event list. *)
  let named_numbers =
    List.filter_map p.numbers ~f:(fun n ->
      Option.map (Card.Value.of_digit n) ~f:(fun v -> Card.Color.Red, v))
  in
  List.dedup_and_sort
    (base @ named_colors @ named_numbers)
    ~compare:(fun (c1, v1) (c2, v2) ->
      match Card.Color.compare c1 c2 with
      | 0 -> Card.Value.compare v1 v2
      | n -> n)
  |> List.mapi ~f:(fun i (color, value) -> card ~color ~value ~id:(100 + i))
;;

let color_domain (p : profile) =
  let named = List.filter p.colors ~f:(fun c -> not (Card.Color.equal c NoColor)) in
  List.dedup_and_sort
    (* NoColor is the flipped-wild opening, where every card matches *)
    ((Card.Color.NoColor :: Red :: Blue :: named))
    ~compare:Card.Color.compare
;;

(* a stack that the played card can continue, one it cannot, and none *)
let stack_domain = [ None; Some Card.Value.Zero; Some Card.Value.Skip ]

(* filler cards only ever get counted, never inspected, so their faces do
   not matter - but their ids must not collide inside one registry *)
let filler ~base n =
  List.init n ~f:(fun i ->
    card ~color:Card.Color.Red ~value:Card.Value.Zero ~id:(base + i))
;;

(* ------------------------------------------------------------------ *)
(* worlds                                                              *)
(* ------------------------------------------------------------------ *)

(* The actor is seat 0 and the opponent seat 1, so "not your turn" is just
   turn = 1 and an opponent always exists for the any-opponent atoms. *)
let actor_id = 0

type world =
  { state : Game_state.t
  ; event : Event.t
  }

(* States and events are built separately and then paired: the state does
   not depend on which card is being played, so building |states| states
   instead of |states| * |cards| keeps the cost of the registry down. *)
(* one point in the state space; each dimension is either varied or pinned
   to the default below *)
type setting =
  { top : Card.t
  ; current_color : Card.Color.t
  ; is_turn : bool
  ; hand : int
  ; opp : int
  ; pending : int
  ; stacking_value : Card.Value.t option
  ; drew_playable : bool
  ; direction : Direction.t
  ; pile : int
  ; uno_vulnerable : int option
  }

(* Pinned values for dimensions nothing reads. They are deliberately TINY:
   every card listed here joins that world's card registry, and a dimension
   no condition asks about cannot change any answer - so a 20-card draw pile
   would be pure cost repeated across every state. *)
let default_setting =
  { top = card ~color:Red ~value:Zero ~id:1
  ; current_color = Card.Color.Red
  ; is_turn = true
  ; hand = 1
  ; opp = 1
  ; pending = 0
  ; stacking_value = None
  ; drew_playable = false
  ; direction = Direction.Clockwise
  ; pile = 1
  ; uno_vulnerable = None
  }
;;

(* cartesian product over the varying dimensions: each entry is a list of
   ways to set one field, and a dimension the conditions never read
   contributes the single identity setter *)
let product (dimensions : (setting -> setting) list list) =
  List.fold dimensions ~init:[ default_setting ] ~f:(fun acc options ->
    List.concat_map acc ~f:(fun s -> List.map options ~f:(fun set -> set s)))
;;

let build_states (p : profile) =
  let dim flag values ~set = if flag then List.map values ~f:set else [ Fn.id ] in
  let dimensions =
    [ dim p.top (card_domain p) ~set:(fun v s -> { s with top = v })
    ; dim p.active_color (color_domain p) ~set:(fun v s -> { s with current_color = v })
    ; dim p.turn [ true; false ] ~set:(fun v s -> { s with is_turn = v })
    ; dim p.hand (numeric_domain p.hand_ns) ~set:(fun v s -> { s with hand = v })
    ; dim p.opp_hand (numeric_domain p.opp_ns) ~set:(fun v s -> { s with opp = v })
    ; dim p.pending (numeric_domain p.pending_ns) ~set:(fun v s ->
        { s with pending = v })
    ; dim p.stack stack_domain ~set:(fun v s -> { s with stacking_value = v })
    ; dim p.drew [ true; false ] ~set:(fun v s -> { s with drew_playable = v })
    ; dim p.direction [ Direction.Clockwise; Counter ] ~set:(fun v s ->
        { s with direction = v })
    ; dim p.draw_pile (numeric_domain p.pile_ns) ~set:(fun v s -> { s with pile = v })
    ; dim p.vulnerable [ None; Some 1 ] ~set:(fun v s -> { s with uno_vulnerable = v })
    ]
  in
  let count =
    List.fold dimensions ~init:1 ~f:(fun acc opts -> acc * List.length opts)
  in
  if count > state_budget
  then None
  else
    Some
      (List.map (product dimensions) ~f:(fun s ->
         Game_state.for_testing
           ~current_color:s.current_color
           ?stacking_value:s.stacking_value
           ~direction:s.direction
           ~drew_playable:s.drew_playable
           ?uno_vulnerable:s.uno_vulnerable
           ~player_hands:
             [ "actor", filler ~base:10_000 s.hand
             ; "opponent", filler ~base:20_000 s.opp
             ]
           ~top_card:s.top
           ~draw_pile:(filler ~base:30_000 s.pile)
           ~pending_draws:s.pending
           ~turn:(if s.is_turn then actor_id else 1)
           ()))
;;

let build_events (p : profile) =
  let actor = Player.create actor_id "actor" in
  let plays =
    let cards =
      if p.played
      then card_domain p
      else [ card ~color:Red ~value:Zero ~id:2 ]
    in
    List.map cards ~f:(fun c ->
      Event.CardPlayed
        { player = actor; card = c; declared_color = None; swap_with = None })
  in
  plays
  @ [ Event.DrawRequested { player = actor }
    ; Event.PassRequested { player = actor }
    ; Event.UnoCalled { player = actor }
    ]
;;

let worlds_for conditions =
  let p = profile_of conditions in
  match build_states p with
  | None -> None
  | Some states ->
    let events = build_events p in
    if List.length states * List.length events > world_budget
    then None
    else
      Some
        (Array.of_list
           (List.concat_map states ~f:(fun state ->
              List.map events ~f:(fun event -> { state; event }))))
;;

(* the satisfying set as a bitmask over the shared world array *)
let mask worlds cond =
  Array.map worlds ~f:(fun { state; event } ->
    Rule_engine.eval_condition state event cond)
;;

let any m = Array.exists m ~f:Fn.id
let subset a b = Array.for_alli a ~f:(fun i x -> (not x) || b.(i))
let disjoint a b = not (Array.existsi a ~f:(fun i x -> x && b.(i)))

(* Is every world [mine] wants claimed by at least one of [others]? Only the
   worlds [mine] actually holds in are examined, and each stops at the first
   coverer, which matters: the naive "union everything, then compare" walks
   every mask in full and allocates one array per coverer. *)
let covered_by_masks mine others =
  let wanted = Array.filter_mapi mine ~f:(fun i x -> if x then Some i else None) in
  (* a rule that can never fire is not "covered"; Impossible_condition
     reports that case on its own *)
  (not (Array.is_empty wanted))
  && Array.for_all wanted ~f:(fun i -> List.exists others ~f:(fun m -> m.(i)))
;;

(* ------------------------------------------------------------------ *)
(* the public questions                                                *)
(* ------------------------------------------------------------------ *)

let compare_masks ma mb =
  if disjoint ma mb
  then Relation.Disjoint
  else (
    match subset ma mb, subset mb ma with
    | true, true -> Equivalent
    | false, true -> Left_subsumes
    | true, false -> Right_subsumes
    | false, false -> Overlap)
;;

let satisfiable cond =
  match worlds_for [ cond ] with
  (* undecidable: assume it can fire rather than accuse it of being dead *)
  | None -> true
  | Some worlds -> any (mask worlds cond)
;;

let relation a b =
  match worlds_for [ a; b ] with
  | None -> Relation.Unknown
  | Some worlds -> compare_masks (mask worlds a) (mask worlds b)
;;

let covered_by cond ~by =
  if List.is_empty by
  then false
  else (
    match worlds_for (cond :: by) with
    | None -> false
    | Some worlds ->
      covered_by_masks (mask worlds cond) (List.map by ~f:(mask worlds)))
;;

(* Whole-ruleset analysis. Building one world set for every rule at once and
   reusing it for all pairs is what makes this affordable: the editor asks
   on every keystroke, and per-pair world construction costs roughly as much
   as the whole batch. Falls back to per-pair when the shared world set
   would be too large. *)
module Batch = struct
  type t =
    { conditions : Rule.Condition.t array
    ; masks : bool array array option (* None: over budget, ask per pair *)
    }

  let create conditions =
    let conditions = Array.of_list conditions in
    let masks =
      match worlds_for (Array.to_list conditions) with
      | None -> None
      | Some worlds -> Some (Array.map conditions ~f:(mask worlds))
    in
    { conditions; masks }
  ;;

  let satisfiable t i =
    match t.masks with
    | Some masks -> any masks.(i)
    | None -> satisfiable t.conditions.(i)
  ;;

  let relation t i j =
    match t.masks with
    | Some masks -> compare_masks masks.(i) masks.(j)
    | None -> relation t.conditions.(i) t.conditions.(j)
  ;;

  let covered_by t i ~by =
    match t.masks with
    | None ->
      covered_by t.conditions.(i) ~by:(List.map by ~f:(fun j -> t.conditions.(j)))
    | Some masks ->
      (not (List.is_empty by))
      && covered_by_masks masks.(i) (List.map by ~f:(fun j -> masks.(j)))
  ;;
end

