open! Core

type t = 
{ id : int
; name : string
; mutable hand: (Int.t, unit) Hashtbl.t
}

let create id name max_hand_size = {
  id;
  name;
  hand = Hashtbl.create (module Int)
}

let get_hand t = t.hand;;

let add_card t card_id = 
  Hashtbl.add_exn t.hand ~key:card_id ~data:() 
;;