(* The shared library of the toy suite: one specification and one body proof per function, each under
   its unit's compspecs (Toy.units.<Unit>.CS) and a context of its callees only.  Both laws use it. *)
Require Import VST.floyd.proofauto.
Require Import VST.floyd.VSU.
Require Toy.units.Counter Toy.units.Pair.
Require Toy.counter.code Toy.pair.code.

Module C.
  Import Toy.counter.code.
  #[export] Instance CS : compspecs := Toy.units.Counter.CS.
  Definition Vprog : varspecs. mk_varspecs Toy.counter.code.prog. Defined.
  Definition t_counter := Tstruct _counter noattr.

  Definition counter_get_spec :=
    DECLARE _counter_get
    WITH c: val, sh: share, n: Z, m: Z
    PRE [ tptr t_counter ]
      PROP (readable_share sh; 0 <= n <= Int.max_unsigned; 0 <= m <= Int.max_unsigned)
      PARAMS (c) SEP (data_at sh t_counter (Vint (Int.repr n), Vint (Int.repr m)) c)
    POST [ tuint ]
      PROP () RETURN (Vint (Int.repr n)) SEP (data_at sh t_counter (Vint (Int.repr n), Vint (Int.repr m)) c).

  Definition counter_inc_spec :=
    DECLARE _counter_inc
    WITH c: val, sh: share, n: Z, m: Z
    PRE [ tptr t_counter ]
      PROP (writable_share sh; 0 <= n <= Int.max_unsigned; 0 <= m <= Int.max_unsigned)
      PARAMS (c) SEP (data_at sh t_counter (Vint (Int.repr n), Vint (Int.repr m)) c)
    POST [ tint ]
      PROP () RETURN (Vint (Int.repr (if zlt n m then 1 else 0)))
      SEP (data_at sh t_counter (Vint (Int.repr (if zlt n m then n + 1 else n)), Vint (Int.repr m)) c).

  Definition Gprog : funspecs := [counter_get_spec; counter_inc_spec].

  Lemma body_counter_get: semax_body Vprog Gprog f_counter_get counter_get_spec.
  Proof. start_function. forward. forward. Qed.

  Lemma body_counter_inc: semax_body Vprog Gprog f_counter_inc counter_inc_spec.
  Proof.
    start_function. forward. forward.
    forward_if.
    - forward. if_tac; [lia | entailer!].
    - forward. forward. forward. if_tac; [entailer! | lia].
  Qed.
End C.

Module P.
  Import Toy.pair.code.
  #[export] Instance CS : compspecs := Toy.units.Pair.CS.
  Definition Vprog : varspecs. mk_varspecs Toy.pair.code.prog. Defined.
  Definition t_pair := Tstruct _pair noattr.

  Definition pair_sum_spec :=
    DECLARE _pair_sum
    WITH p: val, sh: share, a: Z, b: Z
    PRE [ tptr t_pair ]
      PROP (readable_share sh) PARAMS (p) SEP (data_at sh t_pair (Vint (Int.repr a), Vint (Int.repr b)) p)
    POST [ tuint ]
      PROP () RETURN (Vint (Int.add (Int.repr a) (Int.repr b)))
      SEP (data_at sh t_pair (Vint (Int.repr a), Vint (Int.repr b)) p).

  Definition Gprog : funspecs := [pair_sum_spec].

  Lemma body_pair_sum: semax_body Vprog Gprog f_pair_sum pair_sum_spec.
  Proof. start_function. forward. forward. forward. Qed.
End P.
