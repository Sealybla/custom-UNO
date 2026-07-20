open! Core

type t = 
{ id : int
; name : string
; mutable hand: Card.t list
}