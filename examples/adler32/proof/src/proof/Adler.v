(* adler32: a model of the checksum, its specification, and the proof of its body. *)
Require Import VST.floyd.proofauto.
Require Import VST.floyd.VSU.
Require Adler32.units.Adler32.
Require Import Adler32.adler32.code.

#[export] Instance CS : compspecs := Adler32.units.Adler32.CS.
Definition Vprog : varspecs. mk_varspecs Adler32.adler32.code.prog. Defined.

(* ---- the model: RFC 1950's two running sums, modulo 65521 ---- *)
Definition BASE := 65521.
Definition step (s: Z * Z) (x: Z) : Z * Z :=
  let a := (fst s + x) mod BASE in (a, (snd s + a) mod BASE).
Definition run (s: Z * Z) (bs: list Z) : Z * Z := fold_left step bs s.
Definition unpack (adler: Z) : Z * Z := (adler mod 65536, adler / 65536).
Definition pack (s: Z * Z) : Z := snd s * 65536 + fst s.
Definition adler (adler0: Z) (bs: list Z) : Z := pack (run (unpack adler0) bs).

Definition small (s: Z * Z) : Prop := 0 <= fst s < 65536 /\ 0 <= snd s < 65536.

Lemma step_small: forall s x, small s -> small (step s x).
Proof.
  intros [a b] x _. unfold step, small, BASE; simpl.
  pose proof (Z.mod_pos_bound (a + x) 65521 ltac:(lia)).
  pose proof (Z.mod_pos_bound (b + (a + x) mod 65521) 65521 ltac:(lia)). lia.
Qed.

Lemma run_small: forall bs s, small s -> small (run s bs).
Proof. induction bs; intros; simpl; auto. apply IHbs, step_small, H. Qed.

Lemma unpack_small: forall z, 0 <= z <= Int.max_unsigned -> small (unpack z).
Proof.
  intros. unfold unpack, small; simpl.
  pose proof (Z.mod_pos_bound z 65536 ltac:(lia)).
  split; [lia |]. split; [apply Z.div_pos; lia |].
  apply Z.div_lt_upper_bound; rep_lia.
Qed.

Lemma unpack_pack: forall s, small s -> unpack (pack s) = s.
Proof.
  intros [a b] [Ha Hb]; simpl in *. unfold unpack, pack; simpl. f_equal.
  - symmetry. apply Z.mod_unique with b; lia.
  - symmetry. apply Z.div_unique with a; lia.
Qed.

Lemma pack_range: forall s, small s -> 0 <= pack s <= Int.max_unsigned.
Proof. intros [a b] [Ha Hb]; unfold pack; simpl in *; rep_lia. Qed.

Lemma run_app: forall s x y, run s (x ++ y) = run (run s x) y.
Proof. intros. unfold run. apply fold_left_app. Qed.

(* Checksumming in two pieces gives the checksum of the whole. *)
Theorem adler_app: forall a0 x y, 0 <= a0 <= Int.max_unsigned ->
  adler (adler a0 x) y = adler a0 (x ++ y).
Proof.
  intros. unfold adler. rewrite unpack_pack by (apply run_small, unpack_small; auto).
  rewrite run_app. reflexivity.
Qed.

Lemma adler_range: forall a0 bs, 0 <= a0 <= Int.max_unsigned -> 0 <= adler a0 bs <= Int.max_unsigned.
Proof. intros. apply pack_range, run_small, unpack_small; auto. Qed.

(* ---- the specification ---- *)
Definition bytes (bs: list Z) : list val := map (fun b => Vint (Int.repr b)) bs.

Definition adler32_spec :=
  DECLARE _adler32
  WITH adler0: Z, p: val, sh: share, bs: list Z
  PRE [ tuint, tptr tuchar, tulong ]
    PROP (readable_share sh; 0 <= adler0 <= Int.max_unsigned;
          Forall (fun b => 0 <= b <= Byte.max_unsigned) bs; Zlength bs <= Int64.max_unsigned)
    PARAMS (Vint (Int.repr adler0); p; Vlong (Int64.repr (Zlength bs)))
    SEP (data_at sh (tarray tuchar (Zlength bs)) (bytes bs) p)
  POST [ tuint ]
    PROP () RETURN (Vint (Int.repr (adler adler0 bs)))
    SEP (data_at sh (tarray tuchar (Zlength bs)) (bytes bs) p).

Definition Gprog : funspecs := [adler32_spec].

(* ---- machine arithmetic ---- *)
Lemma and_65535: forall z, 0 <= z <= Int.max_unsigned ->
  Int.and (Int.repr z) (Int.repr 65535) = Int.repr (z mod 65536).
Proof.
  intros. change 65535 with (two_p 16 - 1). rewrite <- Int.zero_ext_and by lia.
  rewrite <- (Int.repr_unsigned (Int.zero_ext 16 _)).
  rewrite Int.zero_ext_mod by (cbv; split; congruence). rewrite Int.unsigned_repr by lia. reflexivity.
Qed.

Lemma shru_16: forall z, 0 <= z <= Int.max_unsigned ->
  Int.shru (Int.repr z) (Int.repr 16) = Int.repr (z / 65536).
Proof.
  intros. rewrite Int.shru_div_two_p. rewrite !Int.unsigned_repr by rep_lia. reflexivity.
Qed.

Lemma pack_or: forall a b, 0 <= a < 65536 -> 0 <= b < 65536 ->
  Int.or (Int.shl (Int.repr b) (Int.repr 16)) (Int.repr a) = Int.repr (b * 65536 + a).
Proof.
  intros.
  rewrite Int.shl_mul_two_p, (Int.unsigned_repr 16) by rep_lia. change (two_p 16) with 65536.
  rewrite mul_repr, <- Int.add_is_or, add_repr; [ reflexivity | ].
  apply Int.same_bits_eq. intros i Hi.
  rewrite Int.bits_and, !Int.testbit_repr, Int.bits_zero by auto.
  destruct (zlt i 16).
  - change 65536 with (2 ^ 16). rewrite Z.mul_pow2_bits_low by lia. reflexivity.
  - assert (Z.testbit a i = false).
    { destruct (Z.eq_dec a 0) as [-> | ]; [ apply Z.bits_0 | ].
      apply Z.bits_above_log2; [ lia | ]. apply Z.log2_lt_pow2; [ lia | ].
      apply Z.lt_le_trans with (2 ^ 16); [ lia | apply Z.pow_le_mono_r; lia ]. }
    rewrite H1. apply andb_false_r.
Qed.

Lemma Znth_bytes: forall i bs, 0 <= i < Zlength bs -> Znth i (bytes bs) = Vint (Int.repr (Znth i bs)).
Proof. intros. unfold bytes. rewrite Znth_map by lia. reflexivity. Qed.

Lemma run_snoc: forall s bs i, 0 <= i < Zlength bs ->
  run s (sublist 0 (i + 1) bs) = step (run s (sublist 0 i bs)) (Znth i bs).
Proof.
  intros. rewrite (sublist_split 0 i (i + 1)) by lia. rewrite sublist_len_1 by lia.
  rewrite run_app. reflexivity.
Qed.

(* ---- the body ---- *)
Lemma body_adler32: semax_body Vprog Gprog f_adler32 adler32_spec.
Proof.
  start_function.
  assert (Hs0: small (unpack adler0)) by (apply unpack_small; auto).
  forward. forward.
  rewrite and_65535, shru_16 by auto.
  forward_for_simple_bound (Zlength bs)
    (EX i: Z,
     PROP ()
     LOCAL (temp _a (Vint (Int.repr (fst (run (unpack adler0) (sublist 0 i bs)))));
            temp _b (Vint (Int.repr (snd (run (unpack adler0) (sublist 0 i bs)))));
            temp _buf p; temp _len (Vlong (Int64.repr (Zlength bs))))
     SEP (data_at sh (tarray tuchar (Zlength bs)) (bytes bs) p)).
  - entailer!.
  - assert (Hx: 0 <= Znth i bs <= Byte.max_unsigned) by (apply (proj1 (Forall_Znth _ _) H0); lia).
    pose proof (run_small (sublist 0 i bs) _ Hs0) as [Ha Hb].
    forward.
    { entailer!. rewrite Znth_bytes by lia. simpl. rewrite Int.unsigned_repr by rep_lia. rep_lia. }
    rewrite Znth_bytes by lia.
    forward. forward.
    entailer!.
    rewrite run_snoc by lia. unfold step, BASE; simpl. split; auto.
    pose proof (Z.mod_pos_bound (fst (run (unpack adler0) (sublist 0 i bs)) + Znth i bs) 65521 ltac:(lia)).
    rewrite modu_repr by rep_lia. reflexivity.
  - pose proof (run_small (sublist 0 (Zlength bs) bs) _ Hs0) as [Ha Hb].
    forward.
    entailer!.
    rewrite sublist_same in * by lia.
    rewrite pack_or by auto. reflexivity.
Qed.
