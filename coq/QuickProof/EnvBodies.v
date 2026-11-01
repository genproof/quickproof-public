(* QuickProof.EnvBodies: the bodies of the external functions, proved with VST's semax_ext.

   Not trusted: ordinary proofs, taken from an earlier proof and stated once for every compspecs.  A
   whole-program proof uses them where VST asks for the body of an external function. *)
From Coq Require Import String.
Require Import VST.floyd.proofauto.
Require Import VST.floyd.library.
Require Import QuickProof.Env.
Local Open Scope string_scope.

Ltac env_in :=
  unfold env_specs, nondet_u8_spec, nondet_u32_spec, nondet_size_spec, nondet_bytes_spec,
    gp_assert_spec, gp_assume_spec, malloc_spec', free_spec';
  repeat first [ left; f_equal; reflexivity | right ].
Ltac env_norep := unfold funspecs_norepeat; apply compute_list_norepet_e; reflexivity.
Ltac env_body name :=
  unfold body_lemma_of_funspec, HonestEspec;
  eapply (semax_ext NullExtension.Espec env_link name); [ env_in | env_norep | reflexivity ].

Section Bodies.
Context {CS: compspecs}.

Lemma env_body_malloc : @body_lemma_of_funspec HonestEspec
  (EF_external "quickproof_malloc" (mksignature (AST.Xlong :: nil) AST.Xptr cc_default)) malloc_spec'.
Proof. unfold malloc_spec'. env_body "quickproof_malloc". Qed.

Lemma env_body_free : @body_lemma_of_funspec HonestEspec
  (EF_external "quickproof_free" (mksignature (AST.Xptr :: nil) AST.Xvoid cc_default)) free_spec'.
Proof. unfold free_spec'. env_body "quickproof_free". Qed.

Lemma env_body_u8 : @body_lemma_of_funspec HonestEspec
  (EF_external "nondet_u8" (mksignature nil AST.Xint8unsigned cc_default)) (snd nondet_u8_spec).
Proof. unfold nondet_u8_spec; simpl snd. env_body "nondet_u8". Qed.

Lemma env_body_u32 : @body_lemma_of_funspec HonestEspec
  (EF_external "nondet_u32" (mksignature nil AST.Xint cc_default)) (snd nondet_u32_spec).
Proof. unfold nondet_u32_spec; simpl snd. env_body "nondet_u32". Qed.

Lemma env_body_size : @body_lemma_of_funspec HonestEspec
  (EF_external "nondet_size" (mksignature nil AST.Xlong cc_default)) (snd nondet_size_spec).
Proof. unfold nondet_size_spec; simpl snd. env_body "nondet_size". Qed.

Lemma env_body_bytes : @body_lemma_of_funspec HonestEspec
  (EF_external "nondet_bytes" (mksignature (AST.Xptr :: AST.Xlong :: nil) AST.Xvoid cc_default))
  (snd nondet_bytes_spec).
Proof. unfold nondet_bytes_spec; simpl snd. env_body "nondet_bytes". Qed.

Lemma env_body_assert : @body_lemma_of_funspec HonestEspec
  (EF_external "gp_assert" (mksignature (AST.Xint :: nil) AST.Xvoid cc_default))
  (snd gp_assert_spec).
Proof. unfold gp_assert_spec; simpl snd. env_body "gp_assert". Qed.

Lemma env_body_assume : @body_lemma_of_funspec HonestEspec
  (EF_external "gp_assume" (mksignature (AST.Xint :: nil) AST.Xvoid cc_default))
  (snd gp_assume_spec).
Proof. unfold gp_assume_spec; simpl snd. env_body "gp_assume". Qed.

End Bodies.
