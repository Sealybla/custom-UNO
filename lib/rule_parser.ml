open! Core
open Or_error.Let_syntax

module Token = struct
  type t =
    | Word of string (* lowercased keyword *)
    | Int of int
    | Str of string (* quoted rule name, original case *)
    | Colon
    | Comma
    | LParen
    | RParen
    | Greater

  let to_string = function
    | Word w -> w
    | Int n -> Int.to_string n
    | Str s -> "\"" ^ s ^ "\""
    | Colon -> ":"
    | Comma -> ","
    | LParen -> "("
    | RParen -> ")"
    | Greater -> ">"
  ;;
end

(* every token carries the 1-based line it came from, for error messages *)
type tokens = (Token.t * int) list

let scan_while line i ~f =
  let n = String.length line in
  let rec go j = if j < n && f line.[j] then go (j + 1) else j in
  go i
;;

(* tokens come out reversed; [tokenize] reverses the whole stream once *)
let tokenize_line ~line_num line ~init : tokens Or_error.t =
  let n = String.length line in
  let rec go i acc =
    if i >= n
    then Ok acc
    else (
      let c = line.[i] in
      let punct tok = go (i + 1) ((tok, line_num) :: acc) in
      if Char.is_whitespace c
      then go (i + 1) acc
      else if Char.equal c '#'
      then Ok acc
      else if Char.equal c ':'
      then punct Token.Colon
      else if Char.equal c ','
      then punct Token.Comma
      else if Char.equal c '('
      then punct Token.LParen
      else if Char.equal c ')'
      then punct Token.RParen
      else if Char.equal c '>'
      then punct Token.Greater
      else if Char.equal c '"'
      then (
        match String.index_from line (i + 1) '"' with
        | None -> Or_error.errorf "line %d: unterminated string" line_num
        | Some j ->
          let s = String.sub line ~pos:(i + 1) ~len:(j - i - 1) in
          go (j + 1) ((Token.Str s, line_num) :: acc))
      else if Char.is_digit c
      then (
        let j = scan_while line i ~f:Char.is_digit in
        let s = String.sub line ~pos:i ~len:(j - i) in
        go j ((Token.Int (Int.of_string s), line_num) :: acc))
      else if Char.is_alpha c
      then (
        let j = scan_while line i ~f:Char.is_alphanum in
        let s = String.lowercase (String.sub line ~pos:i ~len:(j - i)) in
        go j ((Token.Word s, line_num) :: acc))
      else Or_error.errorf "line %d: unexpected character '%c'" line_num c)
  in
  go 0 init
;;

let tokenize src : tokens Or_error.t =
  String.split_lines src
  |> List.foldi ~init:(Ok []) ~f:(fun i acc line ->
    let%bind acc = acc in
    tokenize_line ~line_num:(i + 1) line ~init:acc)
  |> Or_error.map ~f:List.rev
;;

let where (toks : tokens) =
  match toks with
  | (tok, line) :: _ -> sprintf "line %d at '%s'" line (Token.to_string tok)
  | [] -> "end of input"
;;

let expect_word (toks : tokens) word =
  match toks with
  | (Token.Word w, _) :: rest when String.equal w word -> Ok rest
  | _ -> Or_error.errorf "expected '%s' (%s)" word (where toks)
;;

(* conditions are fixed multi-word phrases, so each is one pattern match *)
let parse_atom (toks : tokens) : (Rule.Condition.t * tokens) Or_error.t =
  let open Token in
  let open Rule.Condition in
  match toks with
  | (Word "always", _) :: rest -> Ok (Always, rest)
  | (Word "your", _) :: (Word "turn", _) :: rest -> Ok (IsPlayerTurn, rest)
  | (Word "card", _) :: (Word "matches", _) :: (Word "color", _) :: rest ->
    Ok (MatchesTopColor, rest)
  | (Word "card", _) :: (Word "matches", _) :: (Word "value", _) :: rest ->
    Ok (MatchesTopValue, rest)
  | (Word "card", _) :: (Word "is", _) :: (Word "wild", _) :: rest ->
    Ok (IsWildCard, rest)
  | (Word "card", _) :: (Word "is", _) :: (Word "skip", _) :: rest ->
    Ok (IsSkip, rest)
  | (Word "card", _) :: (Word "is", _) :: (Word "reverse", _) :: rest ->
    Ok (IsReverse, rest)
  | (Word "card", _) :: (Word "is", _) :: (Word "plus", _) :: (Word "two", _) :: rest ->
    Ok (IsPlusTwo, rest)
  | (Word "card", _) :: (Word "is", _) :: (Word "plus", _) :: (Word "four", _) :: rest
    -> Ok (IsPlusFour, rest)
  | (Word "pending", _) :: (Word "draws", _) :: (Greater, _) :: (Int n, _) :: rest ->
    Ok (PendingDrawsGreaterThan n, rest)
  | (Word "continues", _) :: (Word "stack", _) :: rest -> Ok (ContinuesStack, rest)
  | (Word "player", _) :: (Word "draws", _) :: rest -> Ok (IsDrawAction, rest)
  | (Word "player", _) :: (Word "passes", _) :: rest -> Ok (IsPassAction, rest)
  | _ -> Or_error.errorf "unknown condition (%s)" (where toks)
;;

(* precedence: not > and > or; parentheses override *)
let rec parse_not (toks : tokens) : (Rule.Condition.t * tokens) Or_error.t =
  match toks with
  | (Token.Word "not", _) :: rest ->
    let%map c, rest = parse_not rest in
    Rule.Condition.Not c, rest
  | (Token.LParen, _) :: rest ->
    let%bind c, rest = parse_or rest in
    (match rest with
     | (Token.RParen, _) :: rest -> Ok (c, rest)
     | _ -> Or_error.errorf "expected ')' (%s)" (where rest))
  | _ -> parse_atom toks

and parse_and toks =
  let%bind c1, rest = parse_not toks in
  match rest with
  | (Token.Word "and", _) :: rest ->
    let%map c2, rest = parse_and rest in
    Rule.Condition.And (c1, c2), rest
  | _ -> Ok (c1, rest)

and parse_or toks =
  let%bind c1, rest = parse_and toks in
  match rest with
  | (Token.Word "or", _) :: rest ->
    let%map c2, rest = parse_or rest in
    Rule.Condition.Or (c1, c2), rest
  | _ -> Ok (c1, rest)
;;

let parse_condition = parse_or

let color_of_word word line : Card.Color.t Or_error.t =
  match word with
  | "red" -> Ok Red
  | "green" -> Ok Green
  | "blue" -> Ok Blue
  | "yellow" -> Ok Yellow
  | _ ->
    Or_error.errorf
      "line %d: unknown color '%s' (expected red, green, blue, yellow, or declared)"
      line
      word
;;

(* one phrase can desugar to several effects, hence the list *)
let parse_effect (toks : tokens) : (Game_state.Effect.t list * tokens) Or_error.t =
  let open Token in
  let open Game_state.Effect in
  match toks with
  | (Word "play", _) :: (Word "the", _) :: (Word "card", _) :: rest ->
    (* winning is checked the moment the card leaves the hand *)
    Ok ([ PlayTriggeringCard; CheckWinner ], rest)
  | (Word "set", _) :: (Word "color", _) :: (Word "from", _) :: (Word "card", _) :: rest
    -> Ok ([ SetColorFromTriggeringCard ], rest)
  | (Word "set", _) :: (Word "color", _) :: (Word "to", _) :: (Word "declared", _) :: rest
    -> Ok ([ SetDeclaredColor ], rest)
  | (Word "set", _) :: (Word "color", _) :: (Word "to", _) :: (Word color, line) :: rest
    ->
    let%map color = color_of_word color line in
    [ SetActiveColor color ], rest
  | (Word "add", _) :: (Int n, _) :: (Word "pending", _) :: (Word "draws", _) :: rest ->
    Ok ([ AddPendingDraws n ], rest)
  | (Word "apply", _) :: (Word "pending", _) :: (Word "draws", _) :: rest ->
    Ok ([ ApplyPendingDraws ], rest)
  | (Word "draw", _) :: (Word "until", _) :: (Word "playable", _) :: rest ->
    Ok ([ DrawUntilPlayable ], rest)
  | (Word "draw", _) :: (Int n, _) :: (Word ("card" | "cards"), _) :: rest
  | (Word "draw", _) :: (Int n, _) :: rest -> Ok ([ ExecuteDraw n ], rest)
  | (Word "reverse", _) :: (Word "direction", _) :: rest -> Ok ([ ReverseDirection ], rest)
  | (Word "open", _) :: (Word "stack", _) :: rest -> Ok ([ SetStackingValue ], rest)
  | (Word "clear", _) :: (Word "stack", _) :: rest -> Ok ([ ClearStackingValue ], rest)
  | (Word "advance", _) :: (Word "turn", _) :: rest -> Ok ([ AdvanceTurn ], rest)
  | (Word "skip", _) :: (Word "next", _) :: (Word "player", _) :: rest ->
    Ok ([ AdvanceTurn; AdvanceTurn ], rest)
  | _ -> Or_error.errorf "unknown effect (%s)" (where toks)
;;

let rec parse_effects toks : (Game_state.Effect.t list * tokens) Or_error.t =
  let%bind effs, rest = parse_effect toks in
  match rest with
  | (Token.Comma, _) :: rest ->
    let%map more, rest = parse_effects rest in
    effs @ more, rest
  | _ -> Ok (effs, rest)
;;

let default_priority = 50

(* called with the tokens after the leading "rule" keyword *)
let parse_rule (toks : tokens) ~id : (Rule.t * tokens) Or_error.t =
  let%bind name, toks =
    match toks with
    | (Token.Str name, _) :: rest -> Ok (name, rest)
    | _ -> Or_error.errorf "expected a quoted rule name after 'rule' (%s)" (where toks)
  in
  Or_error.tag
    ~tag:(sprintf "in rule \"%s\"" name)
    (let%bind priority, toks =
       match toks with
       | (Token.Word "priority", _) :: (Token.Int p, _) :: rest -> Ok (p, rest)
       | (Token.Word "priority", _) :: rest ->
         Or_error.errorf "expected a number after 'priority' (%s)" (where rest)
       | _ -> Ok (default_priority, toks)
     in
     let%bind toks =
       match toks with
       | (Token.Colon, _) :: rest -> Ok rest
       | _ -> Or_error.errorf "expected ':' after the rule header (%s)" (where toks)
     in
     let%bind toks = expect_word toks "when" in
     let%bind condition, toks = parse_condition toks in
     let%bind toks = expect_word toks "do" in
     let%map effects, toks = parse_effects toks in
     let actions = List.map effects ~f:(fun e -> Rule.Action_AST.Mutate e) in
     { Rule.id; priority; condition; actions }, toks)
;;

let parse_ruleset src : Rule.t list Or_error.t =
  let%bind toks = tokenize src in
  let rec go toks acc next_id =
    match toks with
    | [] ->
      (match acc with
       | [] -> Or_error.error_string "no rules found"
       | _ -> Ok (List.rev acc))
    | (Token.Word "rule", _) :: rest ->
      let%bind rule, rest = parse_rule rest ~id:next_id in
      go rest (rule :: acc) (next_id + 1)
    | _ -> Or_error.errorf "expected 'rule' to start a rule (%s)" (where toks)
  in
  go toks [] 1
;;
