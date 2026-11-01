(* find_byte: its specification and the proof of its body. *)
Require Import VST.floyd.proofauto.
Require Import VST.floyd.VSU.
Require Demo.units.Mylib.
Require Import Demo.mylib.code.

#[export] Instance CS : compspecs := Demo.units.Mylib.CS.
Definition Vprog : varspecs. mk_varspecs Demo.mylib.code.prog. Defined.

Definition bytes (bs: list Z) : list val := map (fun b => Vint (Int.repr b)) bs.

Definition find_byte_spec :=
  DECLARE _find_byte
  WITH p: val, sh: share, bs: list Z, c: Z
  PRE [ tptr tuchar, tulong, tuchar ]
    PROP (readable_share sh; Forall (fun b => 0 <= b <= Byte.max_unsigned) bs;
          Zlength bs <= Int64.max_unsigned; 0 <= c <= Byte.max_unsigned)
    PARAMS (p; Vlong (Int64.repr (Zlength bs)); Vint (Int.repr c))
    SEP (data_at sh (tarray tuchar (Zlength bs)) (bytes bs) p)
  POST [ tulong ]
    EX r: Z,
    PROP (0 <= r <= Zlength bs; r < Zlength bs -> Znth r bs = c)
    RETURN (Vlong (Int64.repr r))
    SEP (data_at sh (tarray tuchar (Zlength bs)) (bytes bs) p).

Definition Gprog : funspecs := [find_byte_spec].

Lemma Znth_bytes: forall i bs, 0 <= i < Zlength bs -> Znth i (bytes bs) = Vint (Int.repr (Znth i bs)).
Proof. intros. unfold bytes. rewrite Znth_map by lia. reflexivity. Qed.

Lemma body_find_byte: semax_body Vprog Gprog f_find_byte find_byte_spec.
Proof.
  start_function.
  forward.
  forward_loop
    (EX i: Z,
     PROP (0 <= i <= Zlength bs)
     LOCAL (temp _i (Vlong (Int64.repr i)); temp _buf p; temp _n (Vlong (Int64.repr (Zlength bs)));
            temp _c (Vint (Int.repr c)))
     SEP (data_at sh (tarray tuchar (Zlength bs)) (bytes bs) p))
  break:
    (EX i: Z,
     PROP (0 <= i <= Zlength bs; i < Zlength bs -> Znth i bs = c)
     LOCAL (temp _i (Vlong (Int64.repr i)))
     SEP (data_at sh (tarray tuchar (Zlength bs)) (bytes bs) p)).
  - Exists 0. entailer!.
  - Intros i.
    forward_if (PROP ()
                LOCAL (temp _t'1 (Vint (if zlt i (Zlength bs)
                                        then (if Z.eq_dec (Znth i bs) c then Int.zero else Int.one)
                                        else Int.zero));
                       temp _i (Vlong (Int64.repr i)); temp _buf p;
                       temp _n (Vlong (Int64.repr (Zlength bs))); temp _c (Vint (Int.repr c)))
                SEP (data_at sh (tarray tuchar (Zlength bs)) (bytes bs) p)).
    + assert (Hx: 0 <= Znth i bs <= Byte.max_unsigned) by (apply (proj1 (Forall_Znth _ _) H); lia).
      forward.
      { entailer!. rewrite Znth_bytes by lia. simpl. rewrite Int.unsigned_repr by rep_lia. rep_lia. }
      rewrite Znth_bytes by lia.
      forward.
      entailer!.
      rewrite if_true by lia.
      destruct (Z.eq_dec (Znth i bs) c) as [E | E].
      * rewrite E. destruct (zeq c c); [ reflexivity | contradiction ].
      * destruct (zeq (Znth i bs) c); [ contradiction | reflexivity ].
    + forward. entailer!. rewrite if_false by lia. reflexivity.
    + forward_if.
      * forward. Exists (i + 1). entailer!.
        destruct (zlt i (Zlength bs)); [ lia | ]. contradiction H3; reflexivity.
      * forward. Exists i. entailer!.
        rewrite if_true in H3 by lia.
        destruct (Z.eq_dec (Znth i bs) c); [ auto | exfalso; apply Int.one_not_zero; exact H3 ].
  - Intros i. forward. Exists i. entailer!.
Qed.
