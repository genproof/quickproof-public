(* rle_decode: its specification and the proof of its body. *)
Require Import VST.floyd.proofauto.
Require Import VST.floyd.VSU.
Require Rle.units.Rle.
Require Import Rle.rle.code.

#[export] Instance CS : compspecs := Rle.units.Rle.CS.
Definition Vprog : varspecs. mk_varspecs Rle.rle.code.prog. Defined.

(* A byte string as C sees it in memory. *)
Definition bytes (bs: list Z) : list val := map (fun b => Vint (Int.repr b)) bs.

(* Any input of n bytes, any output buffer of cap bytes: rle_decode returns some m <= cap and changes nothing
   but the output buffer. *)
Definition rle_decode_spec :=
  DECLARE _rle_decode
  WITH pin: val, pout: val, shi: share, sho: share, bs: list Z, cap: Z, outv: list val
  PRE [ tptr tuchar, tulong, tptr tuchar, tulong ]
    PROP (readable_share shi; writable_share sho;
          Forall (fun b => 0 <= b <= Byte.max_unsigned) bs;
          Zlength bs <= Int64.max_unsigned; 0 <= cap <= Int64.max_unsigned; Zlength outv = cap)
    PARAMS (pin; Vlong (Int64.repr (Zlength bs)); pout; Vlong (Int64.repr cap))
    SEP (data_at shi (tarray tuchar (Zlength bs)) (bytes bs) pin;
         data_at sho (tarray tuchar cap) outv pout)
  POST [ tulong ]
    EX m: Z, EX outv': list val,
    PROP (0 <= m <= cap; Zlength outv' = cap)
    RETURN (Vlong (Int64.repr m))
    SEP (data_at shi (tarray tuchar (Zlength bs)) (bytes bs) pin;
         data_at sho (tarray tuchar cap) outv' pout).

Definition Gprog : funspecs := [rle_decode_spec].

Lemma Znth_bytes: forall i bs, 0 <= i < Zlength bs -> Znth i (bytes bs) = Vint (Int.repr (Znth i bs)).
Proof. intros. unfold bytes. rewrite Znth_map by lia. reflexivity. Qed.

Lemma body_rle_decode: semax_body Vprog Gprog f_rle_decode rle_decode_spec.
Proof.
  start_function.
  forward. forward.
  forward_while
    (EX i: Z, EX m: Z, EX ov: list val,
     PROP (0 <= i <= Zlength bs; 0 <= m <= cap; Zlength ov = cap)
     LOCAL (temp _i (Vlong (Int64.repr i)); temp _m (Vlong (Int64.repr m));
            temp _in pin; temp _n (Vlong (Int64.repr (Zlength bs)));
            temp _out pout; temp _cap (Vlong (Int64.repr cap)))
     SEP (data_at shi (tarray tuchar (Zlength bs)) (bytes bs) pin;
          data_at sho (tarray tuchar cap) ov pout)).
  - Exists 0 0 outv. entailer!.
  - entailer!.
  - assert (Hb: forall j, 0 <= j < Zlength bs -> 0 <= Znth j bs <= Byte.max_unsigned)
      by (intros j Hj; apply (proj1 (Forall_Znth _ _) H); lia).
    forward.
    { entailer!. rewrite Znth_bytes by lia. simpl. specialize (Hb i ltac:(lia)).
      rewrite Int.unsigned_repr by rep_lia. rep_lia. }
    rewrite Znth_bytes by lia.
    forward.
    forward.
    { entailer!. rewrite Znth_bytes by lia. simpl. specialize (Hb (i + 1) ltac:(lia)).
      rewrite Int.unsigned_repr by rep_lia. rep_lia. }
    rewrite Znth_bytes by lia.
    forward.
    assert (Hc: 0 <= Znth i bs <= Byte.max_unsigned) by (apply Hb; lia).
    assert (Hc1: 0 <= Znth (i + 1) bs <= Byte.max_unsigned) by (apply Hb; lia).
    assert (Ez: Int.zero_ext 8 (Int.repr (Znth (i + 1) bs)) = Int.repr (Znth (i + 1) bs)).
    { apply zero_ext_inrange. rewrite Int.unsigned_repr by rep_lia. simpl. rep_lia. }
    rewrite Ez.
    rewrite Int.unsigned_repr by rep_lia.
    forward_if.
    + forward. Exists 0 ov. entailer!.
    + assert (Hfit: Znth i bs <= cap - m).
      { revert H6. unfold Int64.ltu, Int64.sub.
        rewrite (Int64.unsigned_repr cap), (Int64.unsigned_repr m) by rep_lia.
        rewrite !Int64.unsigned_repr by rep_lia. if_tac; [discriminate | lia]. }
      forward_for_simple_bound (Znth i bs)
        (EX k: Z, EX ov2: list val,
         PROP (Zlength ov2 = cap)
         LOCAL (temp _byte (Vint (Int.repr (Znth (i + 1) bs)));
                temp _count (Vlong (Int64.repr (Znth i bs)));
                temp _i (Vlong (Int64.repr i)); temp _m (Vlong (Int64.repr m));
                temp _in pin; temp _n (Vlong (Int64.repr (Zlength bs)));
                temp _out pout; temp _cap (Vlong (Int64.repr cap)))
         SEP (data_at shi (tarray tuchar (Zlength bs)) (bytes bs) pin;
              data_at sho (tarray tuchar cap) ov2 pout)).
      * Exists ov. entailer!.
      * forward.
        Exists (upd_Znth (m + i0) ov2 (Vint (Int.repr (Znth (i + 1) bs)))).
        entailer!.
        { list_solve. }
        cancel.
      * Intros ov2. forward. forward.
        Exists (i + 2, m + Znth i bs, ov2). entailer!.
        split; lia.
  - forward. Exists m ov. entailer!.
Qed.
