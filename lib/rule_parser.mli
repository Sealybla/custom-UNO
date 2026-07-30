open! Core

(* Parses the user-facing rule language (see docs/rule-language.md) into
   engine rules. `use <preset>` lines expand to the named Presets text, and
   a later rule with the same name as an earlier one replaces it in place,
   so preset rules can be redefined without duplication. Ids are assigned
   sequentially after that merge; priority defaults to 50 when omitted.
   The result is compatible with Rule_engine.Ruleset.t. *)
val parse_ruleset : string -> Rule.t List.t Or_error.t
