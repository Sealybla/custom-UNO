open! Core

(* Parses the user-facing rule language (see docs/rule-language.md) into
   engine rules. `use <preset>` lines expand to the named Presets text, and
   a later rule with the same name as an earlier one replaces it in place,
   so preset rules can be redefined without duplication. Ids are assigned
   sequentially after that merge; priority defaults to 50 when omitted.
   The result is compatible with Rule_engine.Ruleset.t. Rules only - the
   tests' entry point; production uses parse_ruleset_full to also get the
   settings directives. *)
val parse_ruleset : string -> Rule.t List.t Or_error.t

(* rules plus the ruleset's settings - directives like `deal N cards` that
   configure the game rather than react to events *)
module Parsed : sig
  type t =
    { rules : Rule.t list
    ; hand_size : int option (* from `deal N cards`; None = the default 7 *)
    ; turn_timer : int option
      (* from `turn timer N seconds` (or `turn timer off` = Some 0);
         None = the server default *)
    }
end

val parse_ruleset_full : string -> Parsed.t Or_error.t

(* parse_ruleset plus lint warnings for editor feedback. Warnings flag
   authoring footguns without rejecting the ruleset: since the engine runs
   only the single highest-priority matching rule per action, a rule that
   wins a card play but omits [play the card] (or [advance turn], or a
   color effect) silently breaks the click. Warnings are structured so the
   editor can offer a one-click fix: [fix] is the snippet to insert, [kind]
   implies where, [rule_name] names the rule to insert it into. *)
module Lint : sig
  module Kind : sig
    type t =
      | Missing_play
      | Missing_advance
      | Missing_set_color (* plays the card but leaves the active color stale *)
      | Missing_turn (* no [your turn] guard: fires for any player, out of turn *)
      | Impossible_condition (* nothing can ever satisfy it *)
      | Unreachable_rule (* rules that outrank it already cover everything it wants *)
      | Ambiguous_overlap
      (* two EQUAL-priority rules overlap, so the winner is whichever was
         typed first - an accident rather than a decision *)
    [@@deriving sexp, compare, equal]
  end

  type t =
    { rule_name : string
    ; kind : Kind.t
    ; message : string
    ; fix : string option (* None: no automatic fix is offered *)
    ; related : string option
      (* the other rule in a two-rule conflict, so the editor can offer the
         choice both ways round instead of only the suggested [fix] *)
    }
  [@@deriving sexp, compare, equal]
end

(* A narrower rule sitting ABOVE a broader one - `play skip` inside `play
   matching card`. Reported separately from warnings because it is the
   normal way to specialise a rule, not a mistake: `standard` alone contains
   six. The same pair ranked the other way round IS a mistake, and appears
   as [Unreachable_rule]. *)
module Specialisation : sig
  type t =
    { specific : string
    ; general : string
    }
  [@@deriving sexp, compare, equal]
end

val parse_ruleset_checked
  :  string
  -> (Parsed.t * Lint.t List.t * Specialisation.t List.t) Or_error.t
