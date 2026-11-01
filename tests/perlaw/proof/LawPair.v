(* Law law_pair of the toy suite: its own program (counter.c, log.c, pair.c and the harness; big.c is not
   linked), proved from the same shared library Toy.proof.Lib as law_count: the body proof of counter_inc
   is the same lemma, moved to this law's compspecs (which has struct pair besides struct counter). *)
Require Import VST.floyd.proofauto.
Require Import VST.floyd.VSU.
Require Import QuickProof.Contract QuickProof.EnvBodies QuickProof.Assembly.
Require Import Toy.proof.Lib.
Require Toy.contracts.law_pair.
Require Import Toy.harness.law_pair.code.

Definition p := Toy.contracts.law_pair.whole_prog.

(* The law's compspecs: the composites of its program. *)
Definition comps := ltac:(let x := eval vm_compute in (prog_composites p) in exact x).
Definition cprog : Clight.program := Clightdefs.mkprogram comps nil nil 1%positive Logic.I.
#[export] Instance CS : compspecs. make_compspecs cprog. Defined.
#[export] Instance CC : change_composite_env C.CS CS. make_cs_preserve C.CS CS. Defined.
#[export] Instance CP : change_composite_env P.CS CS. make_cs_preserve P.CS CS. Defined.

(* main, proved once under the law's compspecs with the shared specs of what it calls *)
Definition Gmain : funspecs := [P.pair_sum_spec; C.counter_inc_spec; gp_assert_spec].

Lemma body_main: semax_body (QPvarspecs p) Gmain f_main (_main, main_spec_std p).
Proof.
  start_function.
  forward. forward.
  forward_call (v_p, Tsh, 1, 2).
  { erewrite (@data_at_change_composite P.CS CS CP Tsh P.t_pair); [ cancel | apply JMeq_refl | reflexivity ]. }
  forward_call.
  forward. forward.
  forward_call (v_c, Tsh, 0, 1).
  { erewrite (@data_at_change_composite C.CS CS CC Tsh C.t_counter); [ cancel | apply JMeq_refl | reflexivity ]. }
  forward_call.
  forward_call (v_c, Tsh, 0 + 1, 1).
  forward_call.
  forward.
  Exists (Int.repr 0). entailer!.
Qed.

(* The law's specifications: main, the shared library's specifications of the linked units' functions
   that the law reaches (with their callees: counter_get is in counter_inc's context), the environment's. *)
Definition G : funspecs :=
  [(_main, QPmain_spec_ext' p tt main_post_TT); P.pair_sum_spec; C.counter_get_spec; C.counter_inc_spec;
   gp_assert_spec].

Theorem law_pair_proved : harness_safe p.
Proof.
  harness_safe_by_specs CS G main_post_TT.
  - reflexivity.
  - entry_shared (semax_body_main_std _ _ p _ _ body_main eq_refl).
    entry_shared P.body_pair_sum.
    entry_shared C.body_counter_get.
    entry_shared C.body_counter_inc.
    entry_external (@external_ok_assert CS).
    apply Forall_nil.
Qed.
