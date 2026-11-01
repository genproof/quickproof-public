Require Import VST.floyd.proofauto.
Require Import VST.floyd.VSU.
Require Demo.units.Mylib.
Require Import Demo.mylib.code.
#[export] Instance CS : compspecs := Demo.units.Mylib.CS.
Definition Vprog : varspecs. mk_varspecs Demo.mylib.code.prog. Defined.

Definition bytes (bs: list Z) : list val := map (fun b => Vint (Int.repr b)) bs.

Lemma Znth_bytes: forall i bs, 0 <= i < Zlength bs -> Znth i (bytes bs) = Vint (Int.repr (Znth i bs)).
Proof. intros. unfold bytes. rewrite Znth_map by lia. reflexivity. Qed.

Definition count_byte_spec :=
  DECLARE _count_byte
  WITH p: val, sh: share, bs: list Z, c: Z
  PRE [ tptr tuchar, tulong, tuchar ]
    PROP (readable_share sh; Zlength bs <= Int64.max_unsigned;
          Forall (fun b => 0 <= b <= Byte.max_unsigned) bs; 0 <= c <= Byte.max_unsigned)
    PARAMS (p; Vlong (Int64.repr (Zlength bs)); Vint (Int.repr c))
    SEP (data_at sh (tarray tuchar (Zlength bs)) (bytes bs) p)
  POST [ tulong ]
    EX r: Z,
    PROP (0 <= r <= Zlength bs; 0 < Zlength bs -> Znth 0 bs = c -> 1 <= r)
    RETURN (Vlong (Int64.repr r))
    SEP (data_at sh (tarray tuchar (Zlength bs)) (bytes bs) p).

Definition Gprog : funspecs := [count_byte_spec].

Lemma body_count_byte: semax_body Vprog Gprog f_count_byte count_byte_spec.
Proof.
  start_function.
  forward.
  forward_for_simple_bound (Zlength bs)
    (EX i: Z, EX k: Z,
     PROP (0 <= k <= i; 0 < i -> Znth 0 bs = c -> 1 <= k)
     LOCAL (temp _k (Vlong (Int64.repr k)); temp _buf p;
            temp _n (Vlong (Int64.repr (Zlength bs))); temp _c (Vint (Int.repr c)))
     SEP (data_at sh (tarray tuchar (Zlength bs)) (bytes bs) p)).
  - Exists 0. entailer!.
  -
    assert (Hb: 0 <= Znth i bs <= Byte.max_unsigned)
      by (apply (proj1 (Forall_Znth _ _) H0); lia).
    forward.
    { entailer!. unfold bytes. rewrite Znth_map by lia. simpl. rewrite Int.unsigned_repr by rep_lia. lia. }
    unfold bytes. rewrite Znth_map by lia.
    forward_if.
    + forward.
      Exists (k + 1). entailer!.
    + forward.
      Exists k. entailer!.
      destruct (Z.eq_dec i 0).
      * subst i. exfalso. apply H5. reflexivity.
      * apply H4; lia.
  - Intros k. forward. Exists k. entailer!.
Qed.
