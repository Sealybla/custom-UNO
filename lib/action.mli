open! Core

(* represents a command input by a player *)
type t =
    | Play of Card.t            (* plays a card in your hand based on id *)
    | Choose of Card.Color.t    (* Changes the color of the play pile *)
    | Draw                      (* Draws a card from the draw pile and places it in your hand *)
    | Uno                       (* Declares UNO *)
    | Quit                      (* Disconnects player from lobby *)


