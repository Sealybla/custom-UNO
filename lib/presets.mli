open! Core

(* Canonical rule-language text of every built-in ruleset. The lobby's
   preset toggles and the parser's `use <preset>` shortcut both expand to
   these; expect tests keep them in lockstep with the hand-coded
   Rule_engine.Ruleset variants. *)

val standard_text : string
val stacking_text : string
val draw_until_text : string
val stacking_draw_until_text : string

(* the four above, again with the out-of-turn jump-in rule appended *)
val jump_in_text : string
val stacking_jump_in_text : string
val draw_until_jump_in_text : string
val stacking_draw_until_jump_in_text : string

(* the seven-zero house rule as an add-on: `use` it AFTER a base preset.
   7s swap hands with the next player, 0s rotate all hands. *)
val seven_zero_text : string

(* (name, text) for every preset, in menu order *)
val all : (string * string) list

(* case-insensitive lookup by preset name as written after `use` *)
val find : string -> string option
val names : string list
