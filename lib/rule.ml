open! Core

(* Rule is basically a condition with a priority and id *)
(* only used for rules *)
module Priority = struct
  type int [@@deriving sexp, compare, equal, bin_io]
end

type t =
  { id : int
  ; priority : Priority.t
  ; condition : Condition.t
  }
[@@deriving sexp, compare, equal, bin_io]
