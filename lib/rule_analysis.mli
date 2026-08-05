open! Core

(* Decides how two rule conditions relate: do they overlap, is one a special
   case of the other, can either fire at all. The linter uses this to report
   genuine contradictions instead of the structural-equality guess it made
   before ("card is red" and "card is red and always" are the same rule, and
   only this module can tell).

   METHOD. Both conditions are evaluated over a finite set of concrete
   worlds - real [Game_state.t] plus [Event.t] pairs - and the resulting
   satisfying sets are compared. Evaluation goes through
   [Rule_engine.eval_condition], the SAME function the engine runs at
   playtime, so the analysis cannot drift from the behaviour it describes,
   and a new condition atom is understood the moment the engine understands
   it. Only the world generator needs to learn to vary a new dimension.

   EXACTNESS. The answer is exact over the abstract domain: worlds vary the
   state dimensions the two conditions actually read, cards come from a
   representative set extended with every colour and number the conditions
   name, and numeric atoms are tested on both sides of each threshold. A
   domain too coarse to separate two conditions could call them
   [Equivalent], so the generator must keep at least two colours, a number
   card, an action card, a wild, matching and non-matching top pairs, and
   both sides of every numeric bound.

   BUDGET. Conditions reading many dimensions at once would need too many
   worlds; past a cap the answer is [Unknown]. Callers must treat [Unknown]
   as "say nothing" - staying silent is right, a false accusation is not. *)

module Relation : sig
  type t =
    | Disjoint (* no situation satisfies both *)
    | Equivalent (* exactly the same situations *)
    | Left_subsumes (* every right situation is also a left one *)
    | Right_subsumes
    | Overlap (* they meet, but neither contains the other *)
    | Unknown (* too large to decide; assume nothing *)
  [@@deriving sexp, compare, equal]
end

(* can this condition ever be true? [false] means the rule is dead on
   arrival - e.g. "card is red and card is blue" *)
val satisfiable : Rule.Condition.t -> bool

val relation : Rule.Condition.t -> Rule.Condition.t -> Relation.t

(* is every situation matching [cond] already matched by one of [by]? Takes a
   LIST because a rule can be shadowed by several higher-priority rules
   together while no single one covers it. [false] when undecidable. *)
val covered_by : Rule.Condition.t -> by:Rule.Condition.t List.t -> bool

(* Answers the same questions for a whole ruleset at once, indexing rules by
   their position in the list given to [create]. Prefer this when asking
   about more than one pair: it builds a single shared world set instead of
   one per pair, which is the difference between the editor's per-keystroke
   check feeling instant and feeling laggy. Falls back to the per-pair
   functions above when the shared set would exceed the budget. *)
module Batch : sig
  type t

  val create : Rule.Condition.t List.t -> t
  val satisfiable : t -> int -> bool
  val relation : t -> int -> int -> Relation.t
  val covered_by : t -> int -> by:int List.t -> bool
end
