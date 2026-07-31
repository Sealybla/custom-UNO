open! Core

(* The canonical text of every built-in ruleset, in the rule language. These
   are the single source of truth behind the lobby preset toggles and the
   parser's `use <preset>` shortcut; expect tests check that each parses to
   its hand-coded Rule_engine.Ruleset twin. Built from shared blocks so the
   variants stay word-for-word consistent with each other. *)

let base_specials =
  {|
rule "play wild" priority 100:
  when card is wild and your turn
  do play the card, set color to declared, advance turn

rule "play skip" priority 100:
  when card is skip and (card matches color or card matches value) and your turn
  do play the card, set color from card, skip next player

rule "play reverse" priority 100:
  when card is reverse and (card matches color or card matches value) and your turn
  do play the card, set color from card, reverse direction, advance turn
|}
;;

(* standard +2/+4: the next player draws immediately and is skipped *)
let immediate_draws =
  {|
rule "play plus two" priority 100:
  when card is plus two and (card matches color or card matches value) and your turn
  do play the card, set color from card, next player draws 2 cards, skip next player

rule "play plus four" priority 110:
  when card is plus four and your turn
  do play the card, set color to declared, next player draws 4 cards, skip next player
|}
;;

(* the stacking variant's specials are blocked while a stack is open *)
let stacking_specials =
  {|
rule "play wild" priority 100:
  when card is wild and your turn and not stack is open
  do play the card, set color to declared, advance turn

rule "play skip" priority 100:
  when card is skip and (card matches color or card matches value) and your turn and not stack is open
  do play the card, set color from card, skip next player

rule "play reverse" priority 100:
  when card is reverse and (card matches color or card matches value) and your turn and not stack is open
  do play the card, set color from card, reverse direction, advance turn
|}
;;

(* stacking +2/+4: bump a shared counter, cashed out later by "take penalty" *)
let deferred_draws =
  {|
rule "play plus two" priority 100:
  when card is plus two and (card matches color or card matches value) and your turn and not stack is open
  do play the card, set color from card, add 2 pending draws, advance turn

rule "play plus four" priority 110:
  when card is plus four and your turn and not stack is open
  do play the card, set color to declared, add 4 pending draws, advance turn

rule "take penalty" priority 105:
  when pending draws > 0 and your turn and not (card is plus two or card is plus four)
  do apply pending draws, advance turn
|}
;;

let generic_play =
  {|
rule "play matching card" priority 10:
  when (card matches color or card matches value) and your turn
  do play the card, set color from card, advance turn
|}
;;

let draw_decide =
  {|
rule "draw a card" priority 1:
  when player draws and your turn and not stack is open and not drew playable card
  do draw and decide
|}
;;

let pass_after_draw =
  {|
rule "pass after draw" priority 1:
  when player passes and your turn and drew playable card
  do advance turn
|}
;;

(* draw-until: drawing never ends the turn and there is no pass rule, so
   only playing a card does *)
let draw_until =
  {|
rule "draw until playable" priority 1:
  when player draws and your turn
  do draw 1 cards
|}
;;

(* draw-until inside the stacking variant: same idea, but no drawing while
   a stack is open (the stack is closed by playing or by done) *)
let draw_until_stack =
  {|
rule "draw until playable" priority 1:
  when player draws and your turn and not stack is open
  do draw 1 cards
|}
;;

let stack_rules =
  {|
rule "open stack" priority 10:
  when (card matches color or card matches value) and your turn and not stack is open
  do play the card, set color from card, open stack

rule "continue stack" priority 120:
  when continues stack and your turn
  do play the card, set color from card

rule "pass on stack" priority 120:
  when player passes and your turn and stack is open
  do close stack, advance turn
|}
;;

(* The UNO button, in every variant. Anyone may press at any time, so
   priority alone decides the race: claiming your own UNO beats catching
   someone else's, which beats a press with nothing behind it. The last
   rule matches any press, so one is always resolved here and never falls
   through to a turn rule. Raise the 2s to make forgetting cost more. *)
let uno_rules =
  {|
rule "call uno" priority 200:
  when player calls uno and has uno
  do mark uno called

rule "catch uno" priority 190:
  when player calls uno and someone has uno
  do penalize uncalled player 2 cards

rule "false uno call" priority 180:
  when player calls uno
  do penalize caller 2 cards
|}
;;

let standard_text =
  base_specials
  ^ immediate_draws
  ^ generic_play
  ^ draw_decide
  ^ pass_after_draw
  ^ uno_rules
;;

let stacking_text =
  stacking_specials
  ^ deferred_draws
  ^ stack_rules
  ^ draw_decide
  ^ pass_after_draw
  ^ uno_rules
;;

let draw_until_text =
  base_specials ^ immediate_draws ^ generic_play ^ draw_until ^ uno_rules
;;

let stacking_draw_until_text =
  stacking_specials ^ deferred_draws ^ stack_rules ^ draw_until_stack ^ uno_rules
;;

let all =
  [ "standard", standard_text
  ; "stacking", stacking_text
  ; "draw until playable", draw_until_text
  ; "stacking with draw until playable", stacking_draw_until_text
  ]
;;

let find name =
  List.Assoc.find all ~equal:String.equal (String.lowercase (String.strip name))
;;

let names = List.map all ~f:fst
