(* Law law_count of the toy suite: its own program (counter.c, log.c and the harness; pair.c and big.c are
   not linked), proved from the shared library Toy.proof.Lib.  counter_reset and log_reset are linked (whole
   units) but no law reaches them: they get vacuous specifications automatically. *)
Require Import VST.floyd.proofauto.
Require Import VST.floyd.VSU.
Require Import QuickProof.Contract QuickProof.EnvBodies QuickProof.Assembly.
Require Import Toy.proof.Lib.
Require Toy.contracts.law_count.
Require Import Toy.harness.law_count.code.

Definition p := Toy.contracts.law_count.whole_prog.

(* The law's compspecs: the composites of its program. *)
Definition comps := ltac:(let x := eval vm_compute in (prog_composites p) in exact x).
Definition cprog : Clight.program := Clightdefs.mkprogram comps nil nil 1%positive Logic.I.
#[export] Instance CS : compspecs. make_compspecs cprog. Defined.
#[export] Instance CC : change_composite_env C.CS CS. make_cs_preserve C.CS CS. Defined.

(* main, proved once under the law's compspecs with the shared specs of what it calls *)
Definition Gmain : funspecs := [C.counter_get_spec; C.counter_inc_spec; nondet_u32_spec; gp_assert_spec].

Lemma body_main: semax_body (QPvarspecs p) Gmain f_main (_main, main_spec_std p).
Proof.
  start_function.
  forward.
  forward_call. Intros m.
  forward.
  forward_call (v_c, Tsh, 0, m).
  forward.
  forward_call.
  { revert H0. destruct (Int.eq (Int.repr m) (Int.repr 0)) eqn:E.
    - apply int_eq_e in E. apply repr_inj_unsigned in E; [ | rep_lia | rep_lia]. subst.
      if_tac; [lia | ]. simpl. intro X; discriminate X.
    - if_tac.
      + simpl. intro X; discriminate X.
      + assert (m = 0) by lia. subst. rewrite Int.eq_true in E. discriminate. }
  forward_call (v_c, Tsh, (if zlt 0 m then 0 + 1 else 0), m).
  { if_tac; rep_lia. }
  forward_call.
  { match goal with Hc: Int.repr _ = Int.zero |- _ => rewrite Int.eq_true in Hc; discriminate Hc end. }
  forward.
  Exists (Int.repr 0). entailer!.
Qed.

(* The law's specifications: main, the shared library's functions it reaches, the environment's. *)
Definition G : funspecs :=
  [(_main, QPmain_spec_ext' p tt main_post_TT); C.counter_get_spec; C.counter_inc_spec;
   nondet_u32_spec; gp_assert_spec].

Theorem law_count_proved : harness_safe p.
Proof.
  harness_safe_by_specs CS G main_post_TT.
  - reflexivity.
  - entry_shared (semax_body_main_std _ _ p _ _ body_main eq_refl).
    entry_shared C.body_counter_get.
    entry_shared C.body_counter_inc.
    entry_external (@external_ok_u32 CS).
    entry_external (@external_ok_assert CS).
    apply Forall_nil.
Qed.
