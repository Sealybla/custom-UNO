open! Core
open! Async

(** Binds a TCP stream to the designated port and serves the game protocol.
    Players create/join isolated rooms by code; each room runs its own
    lobby, ruleset, and game engine loop. [ruleset] is the default every
    new room starts with. *)
val start
  :  ?ruleset:Rule_engine.Ruleset.t
  -> ?hand_size:int (* cards dealt per player (default 7); `deal N cards`
                       in a room's rules overrides it per room *)
  -> ?turn_timer:int (* seconds before the server plays for a stalled human
                        (default 20; 0 = never); `turn timer N seconds` in
                        a room's rules overrides it per room *)
  -> port:int
  -> unit
  -> (Socket.Address.Inet.t, int) Tcp.Server.t Deferred.t
