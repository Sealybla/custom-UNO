open! Core

(* Parses the user-facing rule language (see docs/rule-language.md) into
   engine rules. Rule ids are assigned sequentially in file order and
   priority defaults to 50 when omitted. The result is compatible with
   Rule_engine.Ruleset.t. *)
val parse_ruleset : string -> Rule.t List.t Or_error.t
