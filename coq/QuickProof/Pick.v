(* QuickProof.Pick: the byte-reinterpretation behind pick(x) on an INTEGER SCALAR.

   Not trusted: ordinary VST proofs, every lemma Qed, no Axiom and no Admitted.  (Print Assumptions
   shows only Coq's standard classical/extensionality axioms -- the same ones VST itself uses.)

   pick(x) is nondet_bytes(&x cast to unsigned char star, sizeof x) (include/quickproof.h).  Its postcondition
   (QuickProof.Env.nondet_bytes_spec) leaves, at &x,
       data_at sh (tarray tuchar (sizeof t)) (map (fun b => Vint (Int.repr b)) bs) p
   for an arbitrary in-range byte list bs.  For an integer scalar x : t the harness then wants to use
   x as an ARBITRARY VALUE of type t, i.e. it needs
       ... |-- EX v, data_at sh t (Vint v) p    (or Vlong v for 64-bit t).
   The lemmas below are that reinterpretation: a DERIVED consequence of nondet_bytes_spec (they take
   exactly the footprint that spec leaves), NOT a new assumed spec -- the trusted base (Env.v) is
   untouched.  Soundness is CompCert's own byte<->value correspondence (VST's data_at_int_bytes /
   data_at_long_bytes_forward / data_at_short_bytes): a concrete byte list decodes to SOME value of
   an integer type -- integer chunks have no trap representations -- so "arbitrary bytes => arbitrary
   value" holds.  field_compatible t [] p (the alignment of t at p) is a hypothesis: &x has it
   because x is declared with type t.

   SUPPORTED: tuchar, tuint, tint, tulong, tlong, tushort.
   NOT supported (deliberately excluded, see quickproof.h): tschar and tshort.  A signed sub-word load
   (Mint8signed / Mint16signed) SIGN-extends, so the stored value is not the zero-extended value the
   bytes decode to; backing those would need a separate sign-extension argument and is not done here.
   (tint and tlong are fine: every 32-/64-bit pattern is a valid value of them -- tc_val is
   unconditional -- so they reuse the unsigned byte lemmas via a signedness bridge.) *)
From Coq Require Import List.
Require Import VST.floyd.proofauto.
From compcert Require Import Clightdefs.
Import ListNotations.

Section Pick.
Context {cs: compspecs}.

(* ------------------------------------------------------------------ *)
(* Generic machinery: peel a tuchar array into its bytes.             *)
(* ------------------------------------------------------------------ *)

Lemma fa0_offset1: forall n p,
  0 < n ->
  field_compatible (tarray tuchar n) [] p ->
  field_address0 (tarray tuchar n) [ArraySubsc 1] p = offset_val 1 p.
Proof.
  intros n p Hn FC.
  rewrite field_address0_offset.
  - unfold nested_field_offset, nested_field_rec, gfield_offset. simpl. reflexivity.
  - apply arr_field_compatible0; auto; lia.
Qed.

Lemma tail_fc: forall n p,
  0 <= n ->
  field_compatible (tarray tuchar (n+1)) [] p ->
  field_compatible (tarray tuchar n) [] (offset_val 1 p).
Proof.
  intros n p Hn FC.
  destruct (field_compatible_Tarray_split tuchar 1 (n+1) p) as [FWD _]. lia.
  specialize (FWD FC). destruct FWD as [_ FC2].
  rewrite fa0_offset1 in FC2 by (auto; lia).
  replace (n+1-1) with n in FC2 by lia. auto.
Qed.

(* Peel one byte off the front; offset relative to the current base p.
   The remainder length m is explicit (array of size m+1) so that rewriting with a concrete m
   matches without leaving un-reduced "k-1" subtractions. *)
Lemma peel1: forall sh n m (w: val) (ws: list val) p,
  n = m + 1 -> 0 <= m -> Zlength ws = m ->
  field_compatible (tarray tuchar n) [] p ->
  data_at sh (tarray tuchar n) (w::ws) p =
  (data_at sh tuchar w p *
   data_at sh (tarray tuchar m) ws (offset_val 1 p))%logic.
Proof.
  intros sh n m w ws p Hn Hm Hlen FC. subst n.
  rewrite (split2_data_at_Tarray_tuchar sh (m+1) 1 (w::ws) p) by (try lia; list_solve).
  pose proof (fa0_offset1 (m+1) p ltac:(lia) FC) as HH. unfold tarray in HH. rewrite HH.
  rewrite sublist_0_cons by lia. rewrite sublist_nil.
  rewrite (data_at_tuchar_singleton_array_eq sh w).
  rewrite sublist_1_cons.
  replace (m+1-1) with (Zlength ws) by (rewrite Hlen; lia).
  rewrite sublist_same by lia.
  replace (Zlength ws) with m by lia.
  reflexivity.
Qed.

(* A concrete in-range Z byte reads as a Vubyte. *)
Lemma Vint_repr_Vubyte: forall (z: Z),
  0 <= z <= Byte.max_unsigned ->
  Vint (Int.repr z) = Vubyte (Byte.repr z).
Proof.
  intros z Hz. unfold Vubyte. rewrite Byte.unsigned_repr by rep_lia. reflexivity.
Qed.

(* Signedness bridge for 64-bit (mirrors VST's data_at_tuint_tint for 32-bit). *)
Lemma data_at_tulong_tlong: forall sh v p, data_at sh tulong v p = data_at sh tlong v p.
Proof.
  intros. unfold data_at, field_at. f_equal. unfold field_compatible.
  apply ND_prop_ext.
  assert (align_compatible tulong p <-> align_compatible tlong p); [| tauto].
  destruct p; simpl; try tauto. split; intros.
  + eapply align_compatible_rec_by_value_inv in H; [| reflexivity].
    eapply align_compatible_rec_by_value; [reflexivity |]. auto.
  + eapply align_compatible_rec_by_value_inv in H; [| reflexivity].
    eapply align_compatible_rec_by_value; [reflexivity |]. auto.
Qed.

(* field_compatible bridges: tint/tlong have the same size and alignment chunk as tuint/tulong. *)
Lemma fc_tint_tuint: forall p, field_compatible tint [] p -> field_compatible tuint [] p.
Proof.
  intros p FC. unfold field_compatible in *. destruct FC as [A [B [C [D E]]]].
  repeat split; auto.
  destruct p; simpl in *; auto.
  eapply align_compatible_rec_by_value_inv in D; [| reflexivity].
  eapply align_compatible_rec_by_value; [reflexivity |]. auto.
Qed.

Lemma fc_tlong_tulong: forall p, field_compatible tlong [] p -> field_compatible tulong [] p.
Proof.
  intros p FC. unfold field_compatible in *. destruct FC as [A [B [C [D E]]]].
  repeat split; auto.
  destruct p; simpl in *; auto.
  eapply align_compatible_rec_by_value_inv in D; [| reflexivity].
  eapply align_compatible_rec_by_value; [reflexivity |]. auto.
Qed.

(* ------------------------------------------------------------------ *)
(* Reinterpretation at the Vubyte level (concrete byte values).       *)
(* ------------------------------------------------------------------ *)

(* 1 byte -> tuchar: genuinely trivial (no multi-byte reinterpretation). *)
Lemma reinterpret_tuchar: forall sh (b0: byte) p,
  field_compatible tuchar [] p ->
  data_at sh (tarray tuchar 1) [Vubyte b0] p
    |-- EX v:int, data_at sh tuchar (Vint v) p.
Proof.
  intros sh b0 p FC.
  rewrite (data_at_tuchar_singleton_array_eq sh (Vubyte b0)).
  Exists (Int.repr (Byte.unsigned b0)). cancel.
Qed.

(* 2 bytes -> tushort *)
Lemma reinterpret_tushort: forall sh (b0 b1: byte) p,
  field_compatible tushort [] p ->
  data_at sh (tarray tuchar 2) [Vubyte b0; Vubyte b1] p
    |-- EX v:int, data_at sh tushort (Vint v) p.
Proof.
  intros sh b0 b1 p FCt.
  assert_PROP (field_compatible (tarray tuchar 2) [] p) as FC2 by entailer!.
  assert (FC1: field_compatible (tarray tuchar 1) [] (offset_val 1 p))
    by (apply (tail_fc 1 p); [lia | auto]).
  rewrite (peel1 sh 2 1 (Vubyte b0) [Vubyte b1] p) by (try lia; try list_solve; auto).
  rewrite (peel1 sh 1 0 (Vubyte b1) [] (offset_val 1 p)) by (try lia; try list_solve; auto).
  rewrite !offset_offset_val. simpl.
  Exists (Int.repr (decode_int [b0;b1])).
  sep_apply (data_at_zero_array_inv sh tuchar (@nil val) (offset_val 2 p) eq_refl eq_refl).
  rewrite <- (data_at_short_bytes sh b0 b1 p FCt). cancel.
Qed.

(* 4 bytes -> tuint *)
Lemma reinterpret_tuint: forall sh (b0 b1 b2 b3: byte) p,
  field_compatible tuint [] p ->
  data_at sh (tarray tuchar 4) [Vubyte b0;Vubyte b1;Vubyte b2;Vubyte b3] p
    |-- EX v:int, data_at sh tuint (Vint v) p.
Proof.
  intros sh b0 b1 b2 b3 p FCu.
  assert_PROP (field_compatible (tarray tuchar 4) [] p) as FC4 by entailer!.
  assert (FC3: field_compatible (tarray tuchar 3) [] (offset_val 1 p))
    by (apply (tail_fc 3 p); [lia | auto]).
  assert (FC2: field_compatible (tarray tuchar 2) [] (offset_val 1 (offset_val 1 p)))
    by (apply (tail_fc 2 (offset_val 1 p)); [lia | auto]).
  assert (FC1: field_compatible (tarray tuchar 1) [] (offset_val 1 (offset_val 1 (offset_val 1 p))))
    by (apply (tail_fc 1 (offset_val 1 (offset_val 1 p))); [lia | auto]).
  rewrite (peel1 sh 4 3 (Vubyte b0) [Vubyte b1;Vubyte b2;Vubyte b3] p) by (try lia; try list_solve; auto).
  rewrite (peel1 sh 3 2 (Vubyte b1) [Vubyte b2;Vubyte b3] (offset_val 1 p)) by (try lia; try list_solve; auto).
  rewrite (peel1 sh 2 1 (Vubyte b2) [Vubyte b3] (offset_val 1 (offset_val 1 p))) by (try lia; try list_solve; auto).
  rewrite (peel1 sh 1 0 (Vubyte b3) [] (offset_val 1 (offset_val 1 (offset_val 1 p)))) by (try lia; try list_solve; auto).
  rewrite !offset_offset_val. simpl.
  Exists (Int.repr (decode_int [b0;b1;b2;b3])).
  sep_apply (data_at_zero_array_inv sh tuchar (@nil val) (offset_val 4 p) eq_refl eq_refl).
  sep_apply (data_at_int_bytes eq_refl sh b0 b1 b2 b3 p FCu).
  cancel.
Qed.

(* 4 bytes -> tint (every 32-bit pattern is a valid int) *)
Lemma reinterpret_tint: forall sh (b0 b1 b2 b3: byte) p,
  field_compatible tint [] p ->
  data_at sh (tarray tuchar 4) [Vubyte b0;Vubyte b1;Vubyte b2;Vubyte b3] p
    |-- EX v:int, data_at sh tint (Vint v) p.
Proof.
  intros sh b0 b1 b2 b3 p FCt.
  assert (FCu: field_compatible tuint [] p)
    by (apply fc_tint_tuint; auto).
  sep_apply (reinterpret_tuint sh b0 b1 b2 b3 p FCu).
  Intros v. Exists v. rewrite data_at_tuint_tint. cancel.
Qed.

(* 8 bytes -> tulong *)
Lemma reinterpret_tulong: forall sh (b0 b1 b2 b3 b4 b5 b6 b7: byte) p,
  field_compatible tulong [] p ->
  data_at sh (tarray tuchar 8)
    [Vubyte b0;Vubyte b1;Vubyte b2;Vubyte b3;Vubyte b4;Vubyte b5;Vubyte b6;Vubyte b7] p
    |-- EX v:int64, data_at sh tulong (Vlong v) p.
Proof.
  intros sh b0 b1 b2 b3 b4 b5 b6 b7 p FCl.
  assert_PROP (field_compatible (tarray tuchar 8) [] p) as FC8 by entailer!.
  assert (FC7: field_compatible (tarray tuchar 7) [] (offset_val 1 p))
    by (apply (tail_fc 7 p); [lia|auto]).
  assert (FC6: field_compatible (tarray tuchar 6) [] (offset_val 1 (offset_val 1 p)))
    by (apply (tail_fc 6 (offset_val 1 p)); [lia|auto]).
  assert (FC5: field_compatible (tarray tuchar 5) [] (offset_val 1 (offset_val 1 (offset_val 1 p))))
    by (apply (tail_fc 5 (offset_val 1 (offset_val 1 p))); [lia|auto]).
  assert (FC4: field_compatible (tarray tuchar 4) []
                 (offset_val 1 (offset_val 1 (offset_val 1 (offset_val 1 p)))))
    by (apply (tail_fc 4 (offset_val 1 (offset_val 1 (offset_val 1 p)))); [lia|auto]).
  assert (FC3: field_compatible (tarray tuchar 3) []
                 (offset_val 1 (offset_val 1 (offset_val 1 (offset_val 1 (offset_val 1 p))))))
    by (apply (tail_fc 3 (offset_val 1 (offset_val 1 (offset_val 1 (offset_val 1 p))))); [lia|auto]).
  assert (FC2: field_compatible (tarray tuchar 2) []
                 (offset_val 1 (offset_val 1 (offset_val 1 (offset_val 1 (offset_val 1 (offset_val 1 p)))))))
    by (apply (tail_fc 2 (offset_val 1 (offset_val 1 (offset_val 1 (offset_val 1 (offset_val 1 p)))))); [lia|auto]).
  assert (FC1: field_compatible (tarray tuchar 1) []
                 (offset_val 1 (offset_val 1 (offset_val 1 (offset_val 1 (offset_val 1 (offset_val 1 (offset_val 1 p))))))))
    by (apply (tail_fc 1 (offset_val 1 (offset_val 1 (offset_val 1 (offset_val 1 (offset_val 1 (offset_val 1 p))))))); [lia|auto]).
  rewrite (peel1 sh 8 7 (Vubyte b0) _ p) by (try lia; try list_solve; auto).
  rewrite (peel1 sh 7 6 (Vubyte b1) _ (offset_val 1 p)) by (try lia; try list_solve; auto).
  rewrite (peel1 sh 6 5 (Vubyte b2) _ _) by (try lia; try list_solve; auto).
  rewrite (peel1 sh 5 4 (Vubyte b3) _ _) by (try lia; try list_solve; auto).
  rewrite (peel1 sh 4 3 (Vubyte b4) _ _) by (try lia; try list_solve; auto).
  rewrite (peel1 sh 3 2 (Vubyte b5) _ _) by (try lia; try list_solve; auto).
  rewrite (peel1 sh 2 1 (Vubyte b6) _ _) by (try lia; try list_solve; auto).
  rewrite (peel1 sh 1 0 (Vubyte b7) _ _) by (try lia; try list_solve; auto).
  rewrite !offset_offset_val. simpl.
  Exists (Int64.repr (decode_int [b0;b1;b2;b3;b4;b5;b6;b7])).
  sep_apply (data_at_zero_array_inv sh tuchar (@nil val) (offset_val 8 p) eq_refl eq_refl).
  sep_apply (data_at_long_bytes_forward eq_refl sh b0 b1 b2 b3 b4 b5 b6 b7 p FCl).
  cancel.
Qed.

(* 8 bytes -> tlong (every 64-bit pattern is a valid long) *)
Lemma reinterpret_tlong: forall sh (b0 b1 b2 b3 b4 b5 b6 b7: byte) p,
  field_compatible tlong [] p ->
  data_at sh (tarray tuchar 8)
    [Vubyte b0;Vubyte b1;Vubyte b2;Vubyte b3;Vubyte b4;Vubyte b5;Vubyte b6;Vubyte b7] p
    |-- EX v:int64, data_at sh tlong (Vlong v) p.
Proof.
  intros sh b0 b1 b2 b3 b4 b5 b6 b7 p FCt.
  assert (FCl: field_compatible tulong [] p)
    by (apply fc_tlong_tulong; auto).
  sep_apply (reinterpret_tulong sh b0 b1 b2 b3 b4 b5 b6 b7 p FCl).
  Intros v. Exists v. rewrite data_at_tulong_tlong. cancel.
Qed.

(* ------------------------------------------------------------------ *)
(* Top-level lemmas, in the exact footprint nondet_bytes_spec leaves.  *)
(* These are what a harness proof uses right after the pick(x) call:   *)
(* Intros bs from the postcondition, drop its NULL case (&x is not     *)
(* NULL), then apply the one for x's type.                             *)
(* ------------------------------------------------------------------ *)

Lemma pick_tuchar: forall sh (bs: list Z) p,
  Zlength bs = 1 ->
  Forall (fun b => 0 <= b <= Byte.max_unsigned) bs ->
  field_compatible tuchar [] p ->
  data_at sh (tarray tuchar 1) (map (fun b => Vint (Int.repr b)) bs) p
    |-- EX v:int, data_at sh tuchar (Vint v) p.
Proof.
  intros sh bs p Hlen Hr FC.
  destruct bs as [|z0 [|z1 bs]]; try (exfalso; revert Hlen; list_solve).
  simpl map.
  rewrite (Vint_repr_Vubyte z0 (Forall_inv Hr)).
  apply reinterpret_tuchar; auto.
Qed.

Lemma pick_tushort: forall sh (bs: list Z) p,
  Zlength bs = 2 ->
  Forall (fun b => 0 <= b <= Byte.max_unsigned) bs ->
  field_compatible tushort [] p ->
  data_at sh (tarray tuchar 2) (map (fun b => Vint (Int.repr b)) bs) p
    |-- EX v:int, data_at sh tushort (Vint v) p.
Proof.
  intros sh bs p Hlen Hr FC.
  destruct bs as [|z0 [|z1 [|z2 bs]]]; try (exfalso; revert Hlen; list_solve).
  simpl map.
  pose proof (Forall_inv Hr) as R0. apply Forall_inv_tail in Hr.
  pose proof (Forall_inv Hr) as R1.
  rewrite (Vint_repr_Vubyte z0 R0), (Vint_repr_Vubyte z1 R1).
  apply reinterpret_tushort; auto.
Qed.

Lemma pick_tuint: forall sh (bs: list Z) p,
  Zlength bs = 4 ->
  Forall (fun b => 0 <= b <= Byte.max_unsigned) bs ->
  field_compatible tuint [] p ->
  data_at sh (tarray tuchar 4) (map (fun b => Vint (Int.repr b)) bs) p
    |-- EX v:int, data_at sh tuint (Vint v) p.
Proof.
  intros sh bs p Hlen Hr FC.
  destruct bs as [|z0 [|z1 [|z2 [|z3 [|z4 bs]]]]]; try (exfalso; revert Hlen; list_solve).
  simpl map.
  pose proof (Forall_inv Hr) as R0. apply Forall_inv_tail in Hr.
  pose proof (Forall_inv Hr) as R1. apply Forall_inv_tail in Hr.
  pose proof (Forall_inv Hr) as R2. apply Forall_inv_tail in Hr.
  pose proof (Forall_inv Hr) as R3.
  rewrite (Vint_repr_Vubyte z0 R0), (Vint_repr_Vubyte z1 R1),
          (Vint_repr_Vubyte z2 R2), (Vint_repr_Vubyte z3 R3).
  apply reinterpret_tuint; auto.
Qed.

Lemma pick_tint: forall sh (bs: list Z) p,
  Zlength bs = 4 ->
  Forall (fun b => 0 <= b <= Byte.max_unsigned) bs ->
  field_compatible tint [] p ->
  data_at sh (tarray tuchar 4) (map (fun b => Vint (Int.repr b)) bs) p
    |-- EX v:int, data_at sh tint (Vint v) p.
Proof.
  intros sh bs p Hlen Hr FC.
  destruct bs as [|z0 [|z1 [|z2 [|z3 [|z4 bs]]]]]; try (exfalso; revert Hlen; list_solve).
  simpl map.
  pose proof (Forall_inv Hr) as R0. apply Forall_inv_tail in Hr.
  pose proof (Forall_inv Hr) as R1. apply Forall_inv_tail in Hr.
  pose proof (Forall_inv Hr) as R2. apply Forall_inv_tail in Hr.
  pose proof (Forall_inv Hr) as R3.
  rewrite (Vint_repr_Vubyte z0 R0), (Vint_repr_Vubyte z1 R1),
          (Vint_repr_Vubyte z2 R2), (Vint_repr_Vubyte z3 R3).
  apply reinterpret_tint; auto.
Qed.

Lemma pick_tulong: forall sh (bs: list Z) p,
  Zlength bs = 8 ->
  Forall (fun b => 0 <= b <= Byte.max_unsigned) bs ->
  field_compatible tulong [] p ->
  data_at sh (tarray tuchar 8) (map (fun b => Vint (Int.repr b)) bs) p
    |-- EX v:int64, data_at sh tulong (Vlong v) p.
Proof.
  intros sh bs p Hlen Hr FC.
  destruct bs as [|z0 [|z1 [|z2 [|z3 [|z4 [|z5 [|z6 [|z7 [|z8 bs]]]]]]]]];
    try (exfalso; revert Hlen; list_solve).
  simpl map.
  pose proof (Forall_inv Hr) as R0. apply Forall_inv_tail in Hr.
  pose proof (Forall_inv Hr) as R1. apply Forall_inv_tail in Hr.
  pose proof (Forall_inv Hr) as R2. apply Forall_inv_tail in Hr.
  pose proof (Forall_inv Hr) as R3. apply Forall_inv_tail in Hr.
  pose proof (Forall_inv Hr) as R4. apply Forall_inv_tail in Hr.
  pose proof (Forall_inv Hr) as R5. apply Forall_inv_tail in Hr.
  pose proof (Forall_inv Hr) as R6. apply Forall_inv_tail in Hr.
  pose proof (Forall_inv Hr) as R7.
  rewrite (Vint_repr_Vubyte z0 R0), (Vint_repr_Vubyte z1 R1),
          (Vint_repr_Vubyte z2 R2), (Vint_repr_Vubyte z3 R3),
          (Vint_repr_Vubyte z4 R4), (Vint_repr_Vubyte z5 R5),
          (Vint_repr_Vubyte z6 R6), (Vint_repr_Vubyte z7 R7).
  apply reinterpret_tulong; auto.
Qed.

Lemma pick_tlong: forall sh (bs: list Z) p,
  Zlength bs = 8 ->
  Forall (fun b => 0 <= b <= Byte.max_unsigned) bs ->
  field_compatible tlong [] p ->
  data_at sh (tarray tuchar 8) (map (fun b => Vint (Int.repr b)) bs) p
    |-- EX v:int64, data_at sh tlong (Vlong v) p.
Proof.
  intros sh bs p Hlen Hr FC.
  destruct bs as [|z0 [|z1 [|z2 [|z3 [|z4 [|z5 [|z6 [|z7 [|z8 bs]]]]]]]]];
    try (exfalso; revert Hlen; list_solve).
  simpl map.
  pose proof (Forall_inv Hr) as R0. apply Forall_inv_tail in Hr.
  pose proof (Forall_inv Hr) as R1. apply Forall_inv_tail in Hr.
  pose proof (Forall_inv Hr) as R2. apply Forall_inv_tail in Hr.
  pose proof (Forall_inv Hr) as R3. apply Forall_inv_tail in Hr.
  pose proof (Forall_inv Hr) as R4. apply Forall_inv_tail in Hr.
  pose proof (Forall_inv Hr) as R5. apply Forall_inv_tail in Hr.
  pose proof (Forall_inv Hr) as R6. apply Forall_inv_tail in Hr.
  pose proof (Forall_inv Hr) as R7.
  rewrite (Vint_repr_Vubyte z0 R0), (Vint_repr_Vubyte z1 R1),
          (Vint_repr_Vubyte z2 R2), (Vint_repr_Vubyte z3 R3),
          (Vint_repr_Vubyte z4 R4), (Vint_repr_Vubyte z5 R5),
          (Vint_repr_Vubyte z6 R6), (Vint_repr_Vubyte z7 R7).
  apply reinterpret_tlong; auto.
Qed.

End Pick.

(* gp_pick_scalar: discharge the goal left right after a pick(x) forward_call on an integer scalar.
   Use it when the SEP holds the nondet_bytes footprint on &x and the goal is
   "... |-- EX v, data_at _ t (Vint v / Vlong v) (&x)".  It tries each supported type. *)
Ltac gp_pick_scalar :=
  first
    [ simple apply pick_tuchar
    | simple apply pick_tushort
    | simple apply pick_tuint
    | simple apply pick_tint
    | simple apply pick_tulong
    | simple apply pick_tlong ];
  auto.
