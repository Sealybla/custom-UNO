open! Core

module Color = struct
  type t =
    | Red
    | Green
    | Blue
    | Yellow
    | NoColor
  [@@deriving enumerate, sexp, compare, equal, bin_io]
end

module Value = struct
  type t =
    | Skip
    | Plus
    | Reverse
    | Wild
    | Wild4
    | Zero
    | One
    | Two
    | Three
    | Four
    | Five
    | Six
    | Seven
    | Eight
    | Nine
  [@@deriving enumerate, sexp, compare, equal, bin_io]

  (* the number card for a digit; None outside 0-9 *)
  let of_digit = function
    | 0 -> Some Zero
    | 1 -> Some One
    | 2 -> Some Two
    | 3 -> Some Three
    | 4 -> Some Four
    | 5 -> Some Five
    | 6 -> Some Six
    | 7 -> Some Seven
    | 8 -> Some Eight
    | 9 -> Some Nine
    | _ -> None
  ;;
end

type t =
  { color : Color.t
  ; value : Value.t
  ; id : Int.t
  }
[@@deriving sexp, compare, equal, bin_io]

let get_id t = t.id
let get_color t = t.color
let get_value t = t.value
