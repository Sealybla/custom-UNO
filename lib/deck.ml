open !Core

type t = {remaining : Card.t Queue.t }[@@deriving sexp, bin_io]

(*randomizes array with all cards and adds to queue*)



let array_to_queue (): Card.t Queue.t =
  let arr = 
    
  in 
  let q = Queue.of_array arr in
  q
;;

let create () = 
  {
    remaining = array_to_queue ()
  }

