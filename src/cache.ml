module type Config = sig
  val data : int
  val addr : int
  val line : int
  val size : int
end

module Lru(B : HardCaml.Comb.S)(C : sig val numways : int end) = struct

  open B

  let vwidth = C.numways * (C.numways-1) / 2

  (* note totally sure about the interface to this.
   * it seems you need to first get the lru way (with access=0)
   * then reapply it with (on access) to update the logic.
   * can this be split so they both happen? that would seem
   * to be a better interface for what I have in mind *)

  module I = interface
    current[vwidth]
    access[C.numways]
  end

  module O = interface
    update[vwidth]
    lru_pre[C.numways]
    lru_post[C.numways]
  end

  let idx i j = 
    let rec f n off =
      if n=i then off+j-i-1
      else f (n+1) (off+C.numways-n-1)
    in
    f 0 0

  let upper_diag = 
    let rec g i j = 
      if i = C.numways then []
      else if j = C.numways then g (i+1) (i+2)
      else (i,j) :: g i (j+1)
    in
    g 0 1

  let expand current = 
    Array.init C.numways (fun i ->
      Array.init C.numways (fun j ->
        if i = j then vdd
        else if j > i then bit current (idx i j)
        else ~: (bit current (idx j i))))

  let compress expand = 
    concat @@ List.rev @@ List.map (fun (i,j) -> expand.(i).(j)) upper_diag

  let mask expand access = 
    let access = Array.init (width access) (fun i -> access.[i:i]) in
    Array.mapi 
      (fun i a -> 
        let c = access.(i) in
        Array.mapi 
          (fun j x -> 
            let d = access.(j) in
            if i = j then x
            else mux2 c gnd (mux2 d vdd x)) a) expand (* (!c & (d | x)) = c ? 0 : (d ? 1 : x) *)

  let onehot expand = 
    concat @@ List.rev @@ Array.to_list @@
      Array.map (fun a -> reduce (&:) (Array.to_list a)) expand

  let lru i = 
    let open I in

    let expand = expand i.current in
    let lru_pre = onehot expand in
    let expand = mask expand i.access in
    let update = compress expand in
    let lru_post = onehot expand in

    O.{
      update;
      lru_pre;
      lru_post;
    }
end

module Make(B : Config) = struct

  (* address setup
     [ ..... tag ..... | slot | block | ldbits ] *)

  open HardCaml.Signal.Comb

  let ldbits = HardCaml.Utils.clog2 B.data 
  let tagbits = B.addr - B.size - B.line - ldbits

  let () = assert (B.line >= ldbits)
  let () = assert (tagbits > 0)

  module I = interface
    clk[1] clr[1]
    en[1] rw[1]
    addr[B.addr]
  end
  
  module O = interface
    hit[1]
    addr_o[B.size+B.line]
  end

  (* XXX TODO: allow line = 0 for caches which dont require spatial correlation *)

  let direct_mapped i =
    let open I in
    let module Seq = Utils.Regs(struct let clk=i.clk let clr=i.clr end) in
    assert (width i.addr = B.addr);
    (* address in cache line *)
    let line = try i.addr.[B.line-1:ldbits] with _ -> empty in
    let slot = i.addr.[B.size+B.line-1:B.line] in
    let tag = i.addr.[B.addr-1:B.addr-tagbits] in

    let tag' = Seq.memory (1 lsl B.size) 
      ~we:i.en ~wa:slot ~d:tag ~ra:slot
    in
    let valid = Seq.memory (1 lsl B.size)
      ~c:i.clr ~cv:gnd (* global clear / cache flush *)
      ~we:i.en ~wa:slot ~d:vdd ~ra:slot
    in

    O.({
      hit = valid &: (tag ==: tag');
      addr_o = concat_e [slot; line];
    })

  let set_associative n i = 
    let open I in
    let module Seq = Utils.Regs(struct let clk=i.clk let clr=i.clr end) in
    
    let ln = HardCaml.Utils.clog2 n in
    let line = i.addr.[B.line-1:ldbits] in
    let slot = i.addr.[B.size+B.line-1:B.line] in
    let tag = i.addr.[B.addr-1:B.addr-tagbits] in

    let tags =
      Array.init n (fun _ -> Seq.memory (1 lsl B.size) ~we:i.en ~wa:slot ~d:tag ~ra:slot)
    in

    let matches = Array.map ((==:) tag) tags in
    let hit = reduce (|:) (Array.to_list matches) in

    (* XXX TODO *)

    O.({
      hit;
      addr_o = gnd;
    })

end

