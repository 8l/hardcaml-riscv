module Make_insn_decoder(Ifs : Interfaces.S)(B : HardCaml.Comb.S) : sig

  type t = 
    {
      insn : B.t;
      iclass : B.t Ifs.Class.t;
    }

  val decoder : B.t -> t

end

module Make(Ifs : Interfaces.S) : sig

  open HardCaml.Signal.Comb

  val imm_uj : t -> t

  val decoder : n:int -> inp:t Ifs.I.t -> pipe:t Ifs.Stage.t -> t Ifs.Stage.t

end

