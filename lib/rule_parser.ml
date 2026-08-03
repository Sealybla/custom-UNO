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
  | (Word "card", _) :: (Word "matches", _) :: (Word "exactly", _) :: rest ->
    Ok (MatchesTopExactly, rest)
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
  | (Word "card", _) :: (Word "is", _) :: (Int n, line) :: rest ->
    if n >= 0 && n <= 9
    then Ok (IsNumber n, rest)
    else
      Or_error.errorf
        "line %d: 'card is %d' - card numbers go from 0 to 9"
        line
        n
    (* only the four real colors here, so anything else still falls through
       to the generic unknown-condition error *)
  | (Word "card", _) :: (Word "is", _)
    :: (Word (("red" | "green" | "blue" | "yellow") as color), line) :: rest ->
    let%map color = color_of_word color line in
    IsCardColor color, rest
  | (Word "active", _) :: (Word "color", _) :: (Word "is", _)
    :: (Word color, line) :: rest ->
    let%map color = color_of_word color line in
    ActiveColorIs color, rest
  | (Word "pending", _) :: (Word "draws", _) :: (Greater, _) :: (Int n, _) :: rest ->
    Ok (PendingDrawsGreaterThan n, rest)
  | (Word "continues", _) :: (Word "stack", _) :: rest -> Ok (ContinuesStack, rest)
  | (Word "stack", _) :: (Word "is", _) :: (Word "open", _) :: rest ->
    Ok (StackIsOpen, rest)
  | (Word "drew", _) :: (Word "playable", _) :: (Word "card", _) :: rest ->
    Ok (DrewPlayableCard, rest)
  | (Word "player", _) :: (Word "draws", _) :: rest -> Ok (IsDrawAction, rest)
  | (Word "player", _) :: (Word "passes", _) :: rest -> Ok (IsPassAction, rest)
  | (Word "player", _) :: (Word "calls", _) :: (Word "uno", _) :: rest ->
    Ok (IsUnoCall, rest)
  | (Word "someone", _) :: (Word "has", _) :: (Word "uno", _) :: rest ->
    Ok (SomeoneElseHasUno, rest)
  | (Word "has", _) :: (Word "uno", _) :: rest -> Ok (CallerHasUno, rest)
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
  | (Word "draw", _) :: (Word "and", _) :: (Word "decide", _) :: rest ->
    Ok ([ DrawAndDecide ], rest)
  | (Word "next", _) :: (Word "player", _) :: (Word "draws", _) :: (Int n, _)
    :: (Word ("card" | "cards"), _) :: rest -> Ok ([ DrawForNextPlayer n ], rest)
  | (Word "draw", _) :: (Int n, _) :: (Word ("card" | "cards"), _) :: rest
  | (Word "draw", _) :: (Int n, _) :: rest -> Ok ([ ExecuteDraw n ], rest)
  | (Word "reverse", _) :: (Word "direction", _) :: rest -> Ok ([ ReverseDirection ], rest)
  | (Word "open", _) :: (Word "stack", _) :: rest -> Ok ([ SetStackingValue ], rest)
  (* "clear stack" is the historical spelling; "close stack" reads as the
     natural opposite of "open stack", so both are accepted *)
  | (Word ("close" | "clear"), _) :: (Word "stack", _) :: rest ->
    Ok ([ ClearStackingValue ], rest)
  | (Word "advance", _) :: (Word "turn", _) :: rest -> Ok ([ AdvanceTurn ], rest)
  | (Word "jump", _) :: (Word "in", _) :: rest -> Ok ([ JumpToActor ], rest)
  | (Word "skip", _) :: (Word "next", _) :: (Word "player", _) :: rest ->
    Ok ([ AdvanceTurn; AdvanceTurn ], rest)
  | (Word "swap", _) :: (Word "hands", _) :: (Word "with", _) :: (Word "next", _)
    :: (Word "player", _) :: rest -> Ok ([ SwapHandsWithNext ], rest)
  | (Word "swap", _) :: (Word "hands", _) :: (Word "with", _) :: (Word "chosen", _)
    :: (Word "player", _) :: rest -> Ok ([ SwapHandsWithChosen ], rest)
  | (Word "rotate", _) :: (Word "hands", _) :: rest -> Ok ([ RotateHands ], rest)
  | (Word "everyone", _) :: (Word "else", _) :: (Word "draws", _) :: (Int n, _)
    :: (Word ("card" | "cards"), _) :: rest -> Ok ([ AllOthersDraw n ], rest)
  | (Word "mark", _) :: (Word "uno", _) :: (Word "called", _) :: rest ->
    Ok ([ MarkUnoCalled ], rest)
  | (Word "penalize", _) :: (Word "caller", _) :: (Int n, _)
    :: (Word ("card" | "cards"), _) :: rest -> Ok ([ PenalizeUnoCaller n ], rest)
  | (Word "penalize", _) :: (Word "uncalled", _) :: (Word "player", _) :: (Int n, _)
    :: (Word ("card" | "cards"), _) :: rest -> Ok ([ PenalizeUnoTarget n ], rest)
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

(* called with the tokens after the leading "rule" keyword; ids are
   assigned later, after name-based merging *)
let parse_rule (toks : tokens) : ((string * Rule.t) * tokens) Or_error.t =
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
     (name, { Rule.id = 0; priority; condition; actions }), toks)
;;

let parse_ruleset_named src : (string * Rule.t) list Or_error.t =
  let%bind toks = tokenize src in
  let rec go toks acc ~allow_use =
    match toks with
    | [] -> Ok (List.rev acc)
    | (Token.Word "rule", _) :: rest ->
      let%bind named, rest = parse_rule rest in
      go rest (named :: acc) ~allow_use
    | (Token.Word "use", line) :: rest when allow_use ->
      (* the preset name is every word to the end of the line *)
      let name_words, rest =
        List.split_while rest ~f:(fun (tok, l) ->
          match tok with
          | Token.Word _ -> l = line
          | _ -> false)
      in
      let name =
        String.concat
          ~sep:" "
          (List.map name_words ~f:(fun (tok, _) -> Token.to_string tok))
      in
      (match Presets.find name with
       | None ->
         Or_error.errorf
           "line %d: unknown preset '%s' after 'use' (available: %s)"
           line
           name
           (String.concat ~sep:", " Presets.names)
       | Some text ->
         let%bind preset_toks = tokenize text in
         let%bind included = go preset_toks [] ~allow_use:false in
         go rest (List.rev included @ acc) ~allow_use)
    | _ ->
      Or_error.errorf
        "expected 'rule' or 'use <preset>' to start a line (%s)"
        (where toks)
  in
  let%bind named = go toks [] ~allow_use:true in
  (* a later rule with the same name replaces the earlier one in place, so
     rules pulled in by `use` can be redefined without duplicating them *)
  let merged =
    List.fold named ~init:[] ~f:(fun acc (name, rule) ->
      if List.exists acc ~f:(fun (n, _) -> String.Caseless.equal n name)
      then
        List.map acc ~f:(fun (n, r) ->
          if String.Caseless.equal n name then n, rule else n, r)
      else acc @ [ name, rule ])
  in
  match merged with
  | [] -> Or_error.error_string "no rules found"
  | _ ->
    Ok
      (List.mapi merged ~f:(fun i (name, rule) ->
         name, { rule with Rule.id = i + 1 }))
;;

let parse_ruleset src : Rule.t list Or_error.t =
  Or_error.map (parse_ruleset_named src) ~f:(List.map ~f:snd)
;;

(* -------- lint: authoring footguns worth warning about, not rejecting.
   The engine runs exactly ONE rule per action - the highest-priority match -
   so a rule that wins a card play decides everything that happens to that
   click. Forgetting [play the card] or [advance turn] silently swallows it. *)

(* does the condition positively require an atom satisfying [f]? Atoms under
   an odd number of [not]s don't count: "not (card is plus two)" is a guard,
   not a card-play requirement. *)
let rec condition_requires (cond : Rule.Condition.t) ~positive ~f =
  match cond with
  | And (a, b) | Or (a, b) ->
    condition_requires a ~positive ~f || condition_requires b ~positive ~f
  | Not c -> condition_requires c ~positive:(not positive) ~f
  | atom -> positive && f atom
;;

let is_card_play_atom : Rule.Condition.t -> bool = function
  | MatchesTopColor | MatchesTopValue | MatchesTopExactly | IsWildCard
  | IsSkip | IsReverse | IsPlusTwo | IsPlusFour | IsNumber _
  | IsCardColor _ | ContinuesStack -> true
  | _ -> false
;;

(* mid-stack rules keep the turn on purpose, so they are exempt from the
   "never ends the turn" warning *)
let is_mid_stack_atom : Rule.Condition.t -> bool = function
  | ContinuesStack | StackIsOpen -> true
  | _ -> false
;;

let is_turn_atom : Rule.Condition.t -> bool = function
  | IsPlayerTurn -> true
  | _ -> false
;;

(* UNO presses are never turn-gated, so rules that can only fire on one are
   exempt from the your-turn warning *)
let is_uno_atom : Rule.Condition.t -> bool = function
  | IsUnoCall -> true
  | _ -> false
;;

(* wilds have no printed color, so a wild-play rule must set the color from
   the player's declaration, not from the card *)
let is_wild_atom : Rule.Condition.t -> bool = function
  | IsWildCard | IsPlusFour -> true
  | _ -> false
;;

(* does EVERY way of satisfying [cond] pass through an atom satisfying [f]?
   The dual of [condition_requires] (which asks for SOME path): an Or needs
   both sides to guarantee, and a Not guarantees nothing. *)
let rec condition_guarantees (cond : Rule.Condition.t) ~f =
  match cond with
  | And (a, b) -> condition_guarantees a ~f || condition_guarantees b ~f
  | Or (a, b) -> condition_guarantees a ~f && condition_guarantees b ~f
  | Not _ -> false
  | atom -> f atom
;;

let rec action_uses (act : Rule.Action_AST.t) ~f =
  match act with
  | Mutate eff -> f eff
  | Chain_event _ -> false
  | Sequence acts -> List.exists acts ~f:(action_uses ~f)
;;

(* structured warnings so the editor can offer a one-click fix: the kind
   says which effect is missing, the rule name says where to insert it *)
module Lint = struct
  module Kind = struct
    type t =
      | Missing_play
      | Missing_advance
      | Missing_set_color (* plays the card but leaves the active color stale *)
      | Missing_turn (* no [your turn] guard: fires for any player, out of turn *)
      | Dead_rule (* an identical condition always wins over this rule *)
    [@@deriving sexp, compare, equal]
  end

  type t =
    { rule_name : string
    ; kind : Kind.t
    ; message : string
    ; fix : string option
      (* the snippet a one-click fix inserts (where to insert it is implied
         by [kind]); None means no automatic fix is offered *)
    }
  [@@deriving sexp, compare, equal]
end

let lint (named : (string * Rule.t) list) : Lint.t list =
  List.concat_map named ~f:(fun (name, rule) ->
    let uses f = List.exists rule.actions ~f:(action_uses ~f) in
    let requires f = condition_requires rule.condition ~positive:true ~f in
    let plays =
      uses (function Game_state.Effect.PlayTriggeringCard -> true | _ -> false)
    in
    let ends_turn =
      uses (function
        | Game_state.Effect.AdvanceTurn | SetStackingValue -> true
        | _ -> false)
    in
    let sets_color =
      uses (function
        | Game_state.Effect.SetColorFromTriggeringCard | SetDeclaredColor
        | SetActiveColor _ -> true
        | _ -> false)
    in
    let wild_play = requires is_wild_atom in
    (* when the condition guarantees the played card matches the active
       color, leaving the color untouched is correct, not a mistake *)
    let color_cannot_go_stale =
      condition_guarantees rule.condition ~f:(function
        | Rule.Condition.MatchesTopColor -> true
        | _ -> false)
    in
    List.filter_opt
      [ (if requires is_card_play_atom && not plays
         then
           Some
             { Lint.rule_name = name
             ; kind = Missing_play
             ; message =
                 sprintf
                   "rule \"%s\" fires when a card is played but has no \
                    'play the card' effect - the card will stay in the hand"
                   name
             ; fix = Some "play the card"
             }
         else None)
      ; (if plays && (not ends_turn) && not (requires is_mid_stack_atom)
         then
           Some
             { Lint.rule_name = name
             ; kind = Missing_advance
             ; message =
                 sprintf
                   "rule \"%s\" plays the card but has no 'advance turn' \
                    effect - the turn will never end"
                   name
             ; fix = Some "advance turn"
             }
         else None)
        (* a played card should normally become the color to match; with no
           color effect the previous color stays active (a blue 0 played on
           red keeps red active) *)
      ; (if plays && (not sets_color) && not color_cannot_go_stale
         then
           Some
             { Lint.rule_name = name
             ; kind = Missing_set_color
             ; message =
                 (if wild_play
                  then
                    sprintf
                      "rule \"%s\" plays the card but never sets the color \
                       - add 'set color to declared' so the color the \
                       player picks takes effect"
                      name
                  else
                    sprintf
                      "rule \"%s\" plays the card but never sets the color \
                       - the color to match stays what it was, not the \
                       played card's color"
                      name)
             ; fix =
                 Some
                   (if wild_play
                    then "set color to declared"
                    else "set color from card")
             }
         else None)
        (* turn order is enforced ONLY by this condition, so leaving it out
           means the rule fires for any player's action, even out of turn.
           Guaranteed on every path, not just present somewhere: "your turn
           or player draws" still fires on other players' draws. Two
           deliberate shapes are exempt: jump-in rules, which say "not your
           turn" explicitly, and UNO-call rules, which can only fire on the
           (never turn-gated) UNO button. *)
      ; (let guarded = condition_guarantees rule.condition ~f:is_turn_atom in
         let jump_in_style =
           condition_requires rule.condition ~positive:false ~f:is_turn_atom
         in
         let uno_only = condition_guarantees rule.condition ~f:is_uno_atom in
         if (not guarded) && (not jump_in_style) && not uno_only
         then
           Some
             { Lint.rule_name = name
             ; kind = Missing_turn
             ; message =
                 sprintf
                   "rule \"%s\" has no 'your turn' condition - it fires for \
                    ANY player's action, even out of turn (write 'not your \
                    turn' explicitly if jump-in is what you mean)"
                   name
             ; fix = Some "your turn"
             }
         else None)
      ])
;;

(* a rule with the exact same condition as another rule that always beats
   it (higher priority anywhere, or equal priority defined earlier) can
   never fire. Overlapping-but-different conditions are a semantic question
   the linter stays out of; identical ones are a plain mistake. *)
let dead_rule_warnings (named : (string * Rule.t) list) : Lint.t list =
  List.filter_mapi named ~f:(fun i (name, rule) ->
    let killer =
      List.find_mapi named ~f:(fun j (other_name, other) ->
        if j <> i
           && Rule.Condition.equal other.condition rule.condition
           && (other.priority > rule.priority
               || (other.priority = rule.priority && j < i))
        then Some other_name
        else None)
    in
    Option.map killer ~f:(fun killer ->
      { Lint.rule_name = name
      ; kind = Dead_rule
      ; message =
          sprintf
            "rule \"%s\" can never fire - rule \"%s\" has the same \
             condition and always wins (higher priority first; a tie goes \
             to the rule defined first)"
            name
            killer
      ; fix = None (* which of the twins to change is a judgement call *)
      }))
;;

(* parse plus the lint warnings, for editor feedback *)
let parse_ruleset_checked src : (Rule.t list * Lint.t list) Or_error.t =
  let%map named = parse_ruleset_named src in
  List.map named ~f:snd, lint named @ dead_rule_warnings named
;;
