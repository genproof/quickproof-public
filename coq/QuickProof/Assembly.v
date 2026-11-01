(* QuickProof.Assembly: harness_safe of a linked program from per-function obligations, for a suite of laws
   that share one library of function specifications and body proofs.

   Not trusted: definitions and proofs, no axiom.  docs/LINKING.md ("Shared specifications") is the guide.

   - harness_safe_of_entries: VST's semax_prog of a QP.program for a compspecs of our choice, without a
     Component.  The specifications G are a list checked entry by entry (ENTRIES); every external function not
     in G gets VST's vacuous spec.
   - harness_safe_of_specs: the same, where every internal function that G does not specify gets a vacuous
     specification (precondition False) automatically: the functions a law does not reach need no spec and
     no proof (vacuous_internals).
   - semax_body_move: a body proved once, under its unit's compspecs and a small context (V1, G1), holds in
     every law's program that links the unit: under the law's compspecs (cspecs_sub, decided by computation
     with cspecs_sub_by_computation) and in the law's context (find_id for the variables, funspec_sub for the
     functions: ctx_sub).  The environment's specifications at two compspecs: malloc_spec'_sub,
     free_spec'_sub, nondet_bytes_spec_cs.
   - entry_moved and the tactics at the end: one line per library function in a law's proof. *)
Require Import VST.floyd.proofauto.
Require Import VST.veric.Clight_initial_world.
Require Import VST.floyd.assoclists.
Require Import VST.floyd.VSU.
Require Import QuickProof.Contract.
Require Import VST.floyd.library.
Require Import QuickProof.EnvBodies.
From compcert Require Import Maps.
Import ListNotations.

(* ---------------------------------------------------------------------- *)
(* The obligation of one entry (i, phi) of G whose definition is fd       *)
(* ---------------------------------------------------------------------- *)

Definition var_sizes_okb {cs: compspecs} (vars: list (ident * type)) : bool :=
  forallb (fun var : ident * type => sizeof (snd var) <=? Ptrofs.max_unsigned)%Z vars.

(* The cheap, computable part of semaxfunc_InternalInfo *)
Definition internal_static_ok {cs: compspecs} (f: function) (phi: funspec) : bool :=
  (semax_body_params_ok f &&
   forallb (fun it : ident * type => complete_type (@cenv_cs cs) (snd it)) (fn_vars f) &&
   @var_sizes_okb cs (fn_vars f) &&
   eqb_calling_convention (fn_callconv f) (callingconvention_of_funspec phi))%bool.

(* semaxfunc_ExternalInfo without the global-environment lookup (proved once for all) *)
Definition external_ok (Espec: OracleKind) (ef: external_function) (argsig: list type)
    (retsig: type) (cc: calling_convention) (phi: funspec) : Prop :=
  match phi with mk_funspec (argsig', retsig') cc' A P Q NEP NEQ =>
  retsig = retsig' /\ cc = cc' /\
  argsig' = argsig /\
  ef_sig ef = mksignature (map argtype_of_type argsig) (rettype_of_type retsig) cc /\
  (ef_inline ef = false \/ withtype_empty A) /\
  (forall (gx : genviron) (ts : list Type) x (ret : option val),
   Q ts x (make_ext_rval gx (rettype_of_type retsig) ret)
     && !! Builtins0.val_opt_has_rettype ret (rettype_of_type retsig) |-- !! tc_option_val retsig ret) /\
  @semax_external Espec ef A P Q
  end.

Definition entry_ok (Espec: OracleKind) (cs: compspecs) (V: varspecs) (G: funspecs)
    (i: ident) (phi: funspec) (fd: fundef function) : Prop :=
  match fd with
  | Internal f => @internal_static_ok cs f phi = true /\ @semax_body V G cs f (i, phi)
  | External ef argsig retsig cc => external_ok Espec ef argsig retsig cc phi
  end.

(* An entry of G is a function of p (not a builtin) and satisfies its obligation. *)
Definition entry_of_prog (Espec: OracleKind) (cs: compspecs) (p: QP.program function)
    (G: funspecs) (ix: ident * funspec) : Prop :=
  match PTree.get (fst ix) (QP.prog_defs p) with
  | Some (Gfun fd) => entry_ok Espec cs (QPvarspecs p) G (fst ix) (snd ix) fd
  | _ => False
  end.

(* Every internal function of p has an entry in G. *)
Definition internals_specified (p: QP.program function) (G: funspecs) : bool :=
  forallb (fun ig : ident * globdef (fundef function) type =>
             match snd ig with
             | Gfun (Internal _) => id_in_list (fst ig) (map fst G)
             | _ => true
             end)
          (PTree.elements (QP.prog_defs p)).

(* ---------------------------------------------------------------------- *)
(* Auxiliary facts                                                         *)
(* ---------------------------------------------------------------------- *)

Lemma var_sizes_okb_e {cs: compspecs}: forall vs, var_sizes_okb vs = true -> var_sizes_ok vs.
Proof.
  intros. unfold var_sizes_okb, var_sizes_ok in *.
  rewrite forallb_forall in H. rewrite Forall_forall. intros.
  apply H in H0. destruct x as [? t]; simpl in *. lia.
Qed.

Lemma internal_static_ok_e {cs: compspecs}: forall f phi,
  internal_static_ok f phi = true ->
  semax_body_params_ok f = true /\
  Forall (fun it : ident * type => complete_type (@cenv_cs cs) (snd it) = true) (fn_vars f) /\
  var_sizes_ok (fn_vars f) /\
  fn_callconv f = callingconvention_of_funspec phi.
Proof.
  unfold internal_static_ok; intros.
  rewrite !andb_true_iff in H. destruct H as [[[? ?] ?] ?].
  split3; [auto | | split].
  - rewrite forallb_forall in H0. rewrite Forall_forall. auto.
  - apply var_sizes_okb_e; auto.
  - apply eqb_calling_convention_prop; auto.
Qed.

Lemma composite_env_of_QPcomposite_env_irr:
  forall ce1 ce2 H1 H2, ce1 = ce2 ->
  composite_env_of_QPcomposite_env ce1 H1 = composite_env_of_QPcomposite_env ce2 H2.
Proof. intros. subst. f_equal. apply proof_irr. Qed.

Section Generic.
Context (Espec: OracleKind) (cs: compspecs) (p: QP.program function).

Hypothesis NOREP: compute_list_norepet
   (map fst (QP.prog_builtins p) ++ map fst (PTree.elements (QP.prog_defs p))) = true.
Hypothesis CE: QP.prog_comp_env p =
   QPcomposite_env_of_composite_env (@cenv_cs cs) (@ha_env_cs cs) (@la_env_cs cs).
Hypothesis CBC: cenv_built_correctly
   (map compdef_of_compenv_element (sort_rank (PTree.elements (QP.prog_comp_env p)) []))
   (@cenv_cs cs) = Errors.OK tt.

Lemma prog_OK_of_checks: QPprogram_OK p.
Proof.
  split.
  - apply compute_list_norepet_e; auto.
  - rewrite CE. apply QPcompspecs_OK_i; [apply PTree_samedom_ha | apply PTree_samedom_la].
Qed.

Lemma cenv_of_checks: forall H: QPcomposite_env_OK (QP.prog_comp_env p),
  composite_env_of_QPcomposite_env (QP.prog_comp_env p) H = @cenv_cs cs.
Proof.
  intros.
  assert (H': QPcomposite_env_OK
     (QPcomposite_env_of_composite_env (@cenv_cs cs) (@ha_env_cs cs) (@la_env_cs cs)))
    by (rewrite <- CE; exact H).
  rewrite (composite_env_of_QPcomposite_env_irr _ _ H H' CE).
  apply composite_env_of_QPcomposite_env_of_composite_env;
    [apply PTree_samedom_ha | apply PTree_samedom_la].
Qed.

Lemma CBC_of_checks: forall OK: QPprogram_OK p,
  build_composite_env
    (map compdef_of_compenv_element (sort_rank (PTree.elements (QP.prog_comp_env p)) []))
  = Errors.OK (composite_env_of_QPcomposite_env (QP.prog_comp_env p) (projT1 (proj2 OK))).
Proof.
  intros. apply cenv_built_correctly_e. rewrite cenv_of_checks. exact CBC.
Qed.

End Generic.

(* ---------------------------------------------------------------------- *)
(* The main lemma                                                          *)
(* ---------------------------------------------------------------------- *)

Lemma In_QPprog_funct: forall (p: QP.program function) i fd,
  In (i, fd) (QPprog_funct p) <-> PTree.get i (QP.prog_defs p) = Some (Gfun fd).
Proof.
  intros. unfold QPprog_funct. split; intros.
  - apply PTree.elements_complete. revert H.
    induction (PTree.elements (QP.prog_defs p)) as [|[j[|]]]; simpl; intros; auto.
    destruct H; [left; inv H; auto | right; auto].
  - apply PTree.elements_correct in H. revert H.
    induction (PTree.elements (QP.prog_defs p)) as [|[j[|]]]; simpl; intros; auto.
    destruct H; [left; inv H; auto | right; auto].
    destruct H; [inv H | auto].
Qed.

Lemma SF_of_entry (Espec: OracleKind) (cs: compspecs) V G ge i phi fd:
  entry_ok Espec cs V G i phi fd -> In i (map fst G) -> genv_find_func ge i fd ->
  @SF Espec cs V ge G i fd phi.
Proof.
  intros E IN GF. destruct fd as [f | ef argsig retsig cc]; simpl in *.
  - destruct E as [S B]. apply internal_static_ok_e in S. destruct S as [S1 [S2 [S3 S4]]].
    split3; [ | | split3; [ | | split]]; auto.
    rewrite (id_in_list_true_i _ _ IN), S1; reflexivity.
  - destruct phi as [[argsig' retsig'] cc' A P Q NEP NEQ].
    destruct E as [? [? [? [? [? [? ?]]]]]].
    split3; [ | | split3; [ | | split3]]; auto.
Qed.

Section Main.
Context (Espec: OracleKind) (cs: compspecs) (p: QP.program function) (G: funspecs)
  (z: OK_ty) (post: (ident -> val) -> environ -> mpred).

(* computable side conditions *)
Hypothesis NOREP: compute_list_norepet
   (map fst (QP.prog_builtins p) ++ map fst (PTree.elements (QP.prog_defs p))) = true.
Hypothesis CE: QP.prog_comp_env p =
   QPcomposite_env_of_composite_env (@cenv_cs cs) (@ha_env_cs cs) (@la_env_cs cs).
Hypothesis CBC: cenv_built_correctly
   (map compdef_of_compenv_element (sort_rank (PTree.elements (QP.prog_comp_env p)) []))
   (@cenv_cs cs) = Errors.OK tt.
Hypothesis ALIGNED: QPall_initializers_aligned p = true.
Hypothesis EXT_OK: all_unspecified_OK p.
Hypothesis DNB: forallb not_builtin (PTree.elements (QP.prog_defs p)) = true.
Hypothesis FUNS_NOREP: compute_list_norepet (map fst (QPvarspecs p) ++
   map fst (prog_funct' (map of_builtin (QP.prog_builtins p)) ++ QPprog_funct p)) = true.
Hypothesis VG_NOREP: compute_list_norepet (map fst (QPvarspecs p) ++ map fst G) = true.
Hypothesis INTERNALS: internals_specified p G = true.
(* main's specification *)
Hypothesis MAIN: find_id (QP.prog_main p) G = Some (QPmain_spec_ext' p z post).
(* the functions *)
Hypothesis ENTRIES: Forall (entry_of_prog Espec cs p G) G.

Theorem semax_prog_of_entries:
  forall OK CBC',
  @semax_prog Espec cs (wholeprog_of_QPprog p OK CBC') z (QPvarspecs p) G.
Proof.
  intros OK CBC'.
  assert (B_LNR: list_norepet (map fst (QP.prog_builtins p))
               /\ list_norepet (map fst (QPprog_funct p))
               /\ list_disjoint (map fst (QP.prog_builtins p)) (map fst (QPprog_funct p))). {
    apply compute_list_norepet_e in FUNS_NOREP.
    apply list_norepet_append_right in FUNS_NOREP.
    rewrite map_app, map_fst_prog_funct'_map_of_builtin in FUNS_NOREP.
    rewrite list_norepet_app in FUNS_NOREP. tauto. }
  destruct B_LNR as [B_LNR [F_LNR BF_DISJ]].
  assert (DNB': forallb not_builtin' (QPprog_funct p) = true). {
    clear - DNB.
    unfold QPprog_funct. induction (PTree.elements (QP.prog_defs p)) as [|[i[|]]]; simpl in *; auto.
    rewrite andb_true_iff in *|-*. tauto. }
  assert (G_LNR: list_norepet (map fst G)). {
    apply compute_list_norepet_e in VG_NOREP. apply list_norepet_append_right in VG_NOREP; auto. }
  assert (GENTRY: forall i phi, In (i, phi) G -> exists fd,
             PTree.get i (QP.prog_defs p) = Some (Gfun fd) /\
             entry_ok Espec cs (QPvarspecs p) G i phi fd). {
    intros. rewrite Forall_forall in ENTRIES. apply ENTRIES in H.
    unfold entry_of_prog in H; simpl in H.
    destruct (PTree.get i (QP.prog_defs p)) as [[fd|]|]; try contradiction. eauto. }
  assert (Gsub: forall i, In i (map fst G) -> In i (map fst (QPprog_funct p))). {
    intros. apply list_in_map_inv in H. destruct H as [[j phi] [? ?]]. simpl in H; subst j.
    destruct (GENTRY _ _ H0) as [fd [? _]].
    apply (in_map fst (QPprog_funct p) (i, fd)). apply In_QPprog_funct; auto. }
  destruct (augment_funspecs'_exists G (QP.prog_builtins p) (QPprog_funct p)
              B_LNR F_LNR BF_DISJ DNB' G_LNR Gsub) as [G' HG'].
  assert (AUG: augment_funspecs (wholeprog_of_QPprog p OK CBC') G = G'). {
    unfold augment_funspecs.
    change SeparationLogic.prog_funct with prog_funct.
    erewrite prog_funct_QP_prog_funct; [ | reflexivity].
    rewrite HG'. reflexivity. }
  apply augment_funspecs'_e in HG'.
  unfold semax_prog. rewrite AUG.
  split3; [ | | split3; [ | | split]].
  - unfold prog_defs_names. simpl. rewrite map_app, map_fst_map_of_builtin. exact NOREP.
  - red. unfold SeparationLogic.prog_vars; simpl.
    clear - ALIGNED.
    unfold QPall_initializers_aligned in *.
    unfold QPprog_vars in ALIGNED.
    replace (SeparationLogic.prog_vars'
       (map of_builtin (QP.prog_builtins p) ++ PTree.elements (QP.prog_defs p)))
      with (SeparationLogic.prog_vars' (PTree.elements (QP.prog_defs p)))
      by (induction (QP.prog_builtins p) as [|[i ?]]; try destruct b; simpl; auto).
    induction (PTree.elements (QP.prog_defs p)) as [|[i?]]; auto.
    destruct g; auto.
    simpl in ALIGNED|-*.
    rewrite andb_true_iff in ALIGNED|-*; destruct ALIGNED; auto.
  - simpl. rewrite (cenv_of_checks cs p CE). reflexivity.
  - change SeparationLogicAsLogicSoundness.MainTheorem.CSHL_MinimumLogic.CSHL_Def.semax_func with semax_func.
    assert (GFF: forall i fd, find_id i (prog_funct (wholeprog_of_QPprog p OK CBC')) = Some fd ->
                genv_find_func (Genv.globalenv (wholeprog_of_QPprog p OK CBC')) i fd). {
      intros. apply find_id_e in H.
      apply semax_prog.find_funct_ptr_exists.
      unfold prog_defs_names; simpl. rewrite map_app, map_fst_map_of_builtin.
      apply compute_list_norepet_e; exact NOREP.
      apply (semax_prog.in_prog_funct_in_prog_defs _ _ _ H). }
    change SeparationLogic.prog_funct with prog_funct.
    change (Genv.globalenv (wholeprog_of_QPprog p OK CBC')) with (QPglobalenv p) in *.
    rewrite (prog_funct_QP_prog_funct _ p OK CBC') in GFF|-* by reflexivity.
    eapply (augment_funspecs_semax_func Espec G); try eassumption.
    + pose proof (all_unspecified_OK_e _ EXT_OK).
      replace (map of_builtin' (QP.prog_builtins p))
        with (prog_funct' (map (@of_builtin function) (QP.prog_builtins p))) in H
        by (clear; induction (QP.prog_builtins p) as [|[i[]]]; simpl; auto; f_equal; auto).
      exact H.
    + intros i phi Hf.
      pose proof (find_id_In_map_fst _ _ _ Hf) as IN.
      apply find_id_e in Hf.
      destruct (GENTRY _ _ Hf) as [fd [Hd E]].
      exists fd. split.
      * rewrite in_app; right. apply In_QPprog_funct; auto.
      * apply SF_of_entry; auto. apply GFF.
        apply find_id_i. rewrite in_app; right. apply In_QPprog_funct; auto.
        rewrite map_app, list_norepet_app, map_fst_prog_funct'_map_of_builtin. split3; auto.
    + apply compute_list_norepet_e; exact FUNS_NOREP.
    + apply compute_list_norepet_e; exact VG_NOREP.
    + intros i fd Hin Hint. rewrite in_app in Hin. destruct Hin as [Hin | Hin].
      * clear - Hin Hint. induction (QP.prog_builtins p) as [|[j[]]]; simpl in Hin; [contradiction|].
        destruct Hin; [inv H; discriminate | auto].
      * apply In_QPprog_funct in Hin. destruct fd; [ | discriminate].
        apply PTree.elements_correct in Hin.
        unfold internals_specified in INTERNALS. rewrite forallb_forall in INTERNALS.
        apply INTERNALS in Hin. simpl in Hin. apply id_in_list_true; auto.
  - simpl.
    unfold QPvarspecs, QPprog_vars, SeparationLogic.prog_vars. simpl.
    clear.
    replace (SeparationLogic.prog_vars'
       (map of_builtin (QP.prog_builtins p) ++ PTree.elements (QP.prog_defs p)))
      with (SeparationLogic.prog_vars' (PTree.elements (QP.prog_defs p)))
      by (induction (QP.prog_builtins p) as [|[i ?]]; try destruct b; simpl; auto).
    induction (PTree.elements (QP.prog_defs p)) as [|[i?]].
    simpl. auto.
    simpl. destruct g; auto.
    simpl.
    rewrite eqb_ident_true by auto.
    rewrite eqb_type_refl by auto.
    simpl; auto.
  - change (prog_main (wholeprog_of_QPprog p OK CBC')) with (QP.prog_main p).
    rewrite (augment_funspecs_find_id_Some _ _ _ HG' G_LNR _ _ MAIN).
    exists post.
    unfold QPmain_spec_ext', main_spec_ext'.
    f_equal.
    unfold main_pre, SeparationLogic.main_pre.
    unfold SeparationLogic.prog_vars. simpl.
    unfold QPprog_vars.
    replace (SeparationLogic.prog_vars'
       (map of_builtin (QP.prog_builtins p) ++ PTree.elements (QP.prog_defs p)))
      with (SeparationLogic.prog_vars' (PTree.elements (QP.prog_defs p)))
      by (clear; induction (QP.prog_builtins p) as [|[i ?]]; try destruct b; simpl; auto).
    extensionality gv rho.
    normalize. f_equal. f_equal. f_equal. f_equal.
    clear.
    induction (PTree.elements (QP.prog_defs p)) as [|[i?]]; auto.
    simpl.
    destruct g; auto.
    f_equal; auto.
Qed.

End Main.

(* ---------------------------------------------------------------------- *)
(* harness_safe                                                            *)
(* ---------------------------------------------------------------------- *)

Theorem harness_safe_of_entries (cs: compspecs) (p: QP.program function) (G: funspecs)
  (post: (ident -> val) -> environ -> mpred)
  (NOREP: compute_list_norepet
     (map fst (QP.prog_builtins p) ++ map fst (PTree.elements (QP.prog_defs p))) = true)
  (CE: QP.prog_comp_env p =
     QPcomposite_env_of_composite_env (@cenv_cs cs) (@ha_env_cs cs) (@la_env_cs cs))
  (CBC: cenv_built_correctly
     (map compdef_of_compenv_element (sort_rank (PTree.elements (QP.prog_comp_env p)) []))
     (@cenv_cs cs) = Errors.OK tt)
  (ALIGNED: QPall_initializers_aligned p = true)
  (EXT_OK: all_unspecified_OK p)
  (DNB: forallb not_builtin (PTree.elements (QP.prog_defs p)) = true)
  (FUNS_NOREP: compute_list_norepet (map fst (QPvarspecs p) ++
     map fst (prog_funct' (map of_builtin (QP.prog_builtins p)) ++ QPprog_funct p)) = true)
  (VG_NOREP: compute_list_norepet (map fst (QPvarspecs p) ++ map fst G) = true)
  (INTERNALS: internals_specified p G = true)
  (MAIN: find_id (QP.prog_main p) G = Some (QPmain_spec_ext' p tt post))
  (ENTRIES: Forall (entry_of_prog (@HonestEspec cs) cs p G) G):
  harness_safe p.
Proof.
  red.
  pose (OK := prog_OK_of_checks cs p NOREP CE).
  exists cs, OK, (CBC_of_checks cs p CE CBC OK), G.
  apply semax_prog_of_entries with (post := post); auto.
Qed.

(* ---------------------------------------------------------------------- *)
(* Proving the entries                                                     *)
(* ---------------------------------------------------------------------- *)

Lemma entry_internal_intro (Espec: OracleKind) (cs: compspecs) (p: QP.program function)
  (G: funspecs) (spec: ident * funspec) (f: function):
  PTree.get (fst spec) (QP.prog_defs p) = Some (Gfun (Internal f)) ->
  @internal_static_ok cs f (snd spec) = true ->
  @semax_body (QPvarspecs p) G cs f spec ->
  entry_of_prog Espec cs p G spec.
Proof.
  intros H S B. unfold entry_of_prog. rewrite H. simpl. destruct spec; auto.
Qed.

Lemma entry_external_intro (Espec: OracleKind) (cs: compspecs) (p: QP.program function)
  (G: funspecs) (spec: ident * funspec) ef argsig retsig cc:
  PTree.get (fst spec) (QP.prog_defs p) = Some (Gfun (External ef argsig retsig cc)) ->
  external_ok Espec ef argsig retsig cc (snd spec) ->
  entry_of_prog Espec cs p G spec.
Proof. intros H E. unfold entry_of_prog. rewrite H. simpl. auto. Qed.

(* Lifting a body lemma proved with small Vprog/Gprog to the whole program's V/G. *)
Lemma semax_body_lift (cs: compspecs) (V Vprog: varspecs) (G Gprog: funspecs) f spec:
  @semax_body Vprog Gprog cs f spec ->
  Forall (fun x => find_id (fst x) V = Some (snd x)) Vprog ->
  Forall (fun x => find_id (fst x) G = Some (snd x)) Gprog ->
  list_norepet (map fst V ++ map fst G) ->
  @semax_body V G cs f spec.
Proof.
  intros B HV HG LNR.
  apply (semax_body_subsumption cs Vprog V Gprog G f spec B).
  apply semax_prog.func_tycontext_sub.
  - intros [j t] Hin. rewrite Forall_forall in HV. apply HV in Hin. simpl in Hin.
    apply find_id_e in Hin; auto.
  - intros [j phi] Hin. rewrite Forall_forall in HG. apply HG in Hin. simpl in Hin.
    apply find_id_e in Hin; auto.
  - apply list_norepet_NoDup; auto.
Qed.

(* ---------------------------------------------------------------------- *)
(* The external functions of the honest environment (QuickProof.Env)         *)
(* ---------------------------------------------------------------------- *)

Section EnvEntries.
Context {cs: compspecs}.

Lemma external_ok_malloc: external_ok (@HonestEspec cs)
  (EF_external "quickproof_malloc" (mksignature (AST.Xlong :: nil) AST.Xptr cc_default))
  (tulong :: nil) (tptr tvoid) cc_default malloc_spec'.
Proof.
  unfold external_ok, malloc_spec'.
  split3; [ | | split3; [ | | split3]]; try reflexivity.
  - left; reflexivity.
  - intros. destruct x as [t gv].
    eapply derives_trans; [apply andp_left1; exact (semax_func_cons_malloc_aux gv gx t ret) | ].
    apply prop_derives. destruct ret; simpl; auto.
  - exact (@env_body_malloc cs).
Qed.

Lemma external_ok_free: external_ok (@HonestEspec cs)
  (EF_external "quickproof_free" (mksignature (AST.Xptr :: nil) AST.Xvoid cc_default))
  (tptr tvoid :: nil) tvoid cc_default free_spec'.
Proof.
  unfold external_ok, free_spec'.
  split3; [ | | split3; [ | | split3]]; try reflexivity.
  - left; reflexivity.
  - intros. apply prop_right. simpl. auto.
  - exact (@env_body_free cs).
Qed.

Lemma external_ok_assert: external_ok (@HonestEspec cs)
  (EF_external "gp_assert" (mksignature (AST.Xint :: nil) AST.Xvoid cc_default))
  (tint :: nil) tvoid cc_default (snd gp_assert_spec).
Proof.
  unfold external_ok, gp_assert_spec; simpl snd.
  split3; [ | | split3; [ | | split3]]; try reflexivity.
  - left; reflexivity.
  - intros. apply prop_right. simpl. auto.
  - exact (@env_body_assert cs).
Qed.

Lemma external_ok_assume: external_ok (@HonestEspec cs)
  (EF_external "gp_assume" (mksignature (AST.Xint :: nil) AST.Xvoid cc_default))
  (tint :: nil) tvoid cc_default (snd gp_assume_spec).
Proof.
  unfold external_ok, gp_assume_spec; simpl snd.
  split3; [ | | split3; [ | | split3]]; try reflexivity.
  - left; reflexivity.
  - intros. apply prop_right. simpl. auto.
  - exact (@env_body_assume cs).
Qed.

Lemma external_ok_bytes: external_ok (@HonestEspec cs)
  (EF_external "nondet_bytes" (mksignature (AST.Xptr :: AST.Xlong :: nil) AST.Xvoid cc_default))
  (tptr tuchar :: tulong :: nil) tvoid cc_default (snd nondet_bytes_spec).
Proof.
  unfold external_ok, nondet_bytes_spec; simpl snd.
  split3; [ | | split3; [ | | split3]]; try reflexivity.
  - left; reflexivity.
  - intros. apply prop_right. simpl. auto.
  - exact (@env_body_bytes cs).
Qed.

Lemma external_ok_size: external_ok (@HonestEspec cs)
  (EF_external "nondet_size" (mksignature nil AST.Xlong cc_default))
  nil tulong cc_default (snd nondet_size_spec).
Proof.
  unfold external_ok, nondet_size_spec; simpl snd.
  split3; [ | | split3; [ | | split3]]; try reflexivity.
  - left; reflexivity.
  - intros. simpl. apply andp_left1. Intros n.
    unfold PROPx, LOCALx, SEPx, local, lift1; simpl; unfold_lift. Intros.
    apply prop_right.
    destruct ret as [v|]; unfold eval_id in H0; simpl in H0; [subst v; simpl | discriminate].
    all: try rewrite Int.unsigned_repr by rep_lia; try rep_lia; auto.
  - exact (@env_body_size cs).
Qed.

Lemma external_ok_u8: external_ok (@HonestEspec cs)
  (EF_external "nondet_u8" (mksignature nil AST.Xint8unsigned cc_default))
  nil tuchar cc_default (snd nondet_u8_spec).
Proof.
  unfold external_ok, nondet_u8_spec; simpl snd.
  split3; [ | | split3; [ | | split3]]; try reflexivity.
  - left; reflexivity.
  - intros. simpl. apply andp_left1. Intros n.
    unfold PROPx, LOCALx, SEPx, local, lift1; simpl; unfold_lift. Intros.
    apply prop_right.
    destruct ret as [v|]; unfold eval_id in H0; simpl in H0; [subst v; simpl | discriminate].
    all: try rewrite Int.unsigned_repr by rep_lia; try rep_lia; auto.
  - exact (@env_body_u8 cs).
Qed.

Lemma external_ok_u32: external_ok (@HonestEspec cs)
  (EF_external "nondet_u32" (mksignature nil AST.Xint cc_default))
  nil tuint cc_default (snd nondet_u32_spec).
Proof.
  unfold external_ok, nondet_u32_spec; simpl snd.
  split3; [ | | split3; [ | | split3]]; try reflexivity.
  - left; reflexivity.
  - intros. simpl. apply andp_left1. Intros n.
    unfold PROPx, LOCALx, SEPx, local, lift1; simpl; unfold_lift. Intros.
    apply prop_right.
    destruct ret as [v|]; unfold eval_id in H0; simpl in H0; [subst v; simpl | discriminate].
    all: try rewrite Int.unsigned_repr by rep_lia; try rep_lia; auto.
  - exact (@env_body_u32 cs).
Qed.

End EnvEntries.

(* ---------------------------------------------------------------------- *)
(* Tactics                                                                 *)
(* ---------------------------------------------------------------------- *)

(* Forall P l, element by element (l may be a constant, a cons list or an app of lists). *)
Ltac forall_each tac :=
  repeat (first [ apply Forall_nil | apply Forall_cons; [ tac | ] ]).

(* Forall (fun x => find_id (fst x) G = Some (snd x)) Gprog: every spec of Gprog is in G. *)
Ltac find_ids_G := forall_each reflexivity.
(* Forall (fun x => find_id (fst x) (QPvarspecs p) = Some (snd x)) Vprog *)
Ltac find_ids_V := forall_each ltac:(vm_compute; reflexivity).

(* semax_body V G f spec from a body lemma B : semax_body Vprog Gprog f spec;
   LNR : list_norepet (map fst V ++ map fst G). *)
Ltac lift_body B LNR :=
  eapply semax_body_lift; [ exact B | find_ids_V | find_ids_G | exact LNR ].

(* Goal Forall (entry_of_prog Espec cs p G) (spec :: rest): discharge the head entry, an
   internal function, with its body lemma B; leaves Forall ... rest. *)
Ltac entry_internal B LNR :=
  lazymatch type of B with
  | @semax_body _ _ _ ?f ?spec =>
    apply Forall_cons;
    [ apply (entry_internal_intro _ _ _ _ spec f);
      [ reflexivity | vm_compute; reflexivity | lift_body B LNR ]
    | ]
  end.

(* The head entry is an external function; L : external_ok Espec ef argsig retsig cc phi
   (e.g. external_ok_malloc). *)
Ltac entry_external L :=
  apply Forall_cons; [ eapply entry_external_intro; [ | exact L ]; reflexivity | ].

(* Goal harness_safe p: apply harness_safe_of_entries with compspecs cs, specs G and main's
   postcondition post, and prove its computable side conditions.  Leaves two goals:
   MAIN (find_id (QP.prog_main p) G = Some (QPmain_spec_ext' p tt post), usually reflexivity)
   and ENTRIES (Forall (entry_of_prog (HonestEspec cs) cs p G) G). *)
Ltac harness_safe_by_entries cs G post :=
  apply (harness_safe_of_entries cs _ G post);
  [ vm_compute; reflexivity
  | vm_compute; reflexivity
  | vm_compute; reflexivity
  | vm_compute; reflexivity
  | red; vm_compute; reflexivity
  | vm_compute; reflexivity
  | vm_compute; reflexivity
  | vm_compute; reflexivity
  | vm_compute; reflexivity
  | | ].


(* ---------------------------------------------------------------------- *)
(* Vacuous specifications for the internal functions G does not specify    *)
(* ---------------------------------------------------------------------- *)

Definition unspecified_internal (G: funspecs) (ifd: ident * fundef function) : bool :=
  match snd ifd with Internal _ => negb (id_in_list (fst ifd) (map fst G)) | External _ _ _ _ => false end.

(* Every internal function of p that G does not specify, with VST's vacuous spec (precondition False). *)
Definition vacuous_internals (p: QP.program function) (G: funspecs) : funspecs :=
  map (fun ifd => (fst ifd, vacuous_funspec (snd ifd))) (filter (unspecified_internal G) (QPprog_funct p)).

(* The computable conditions of their entries (complete local types, parameters, sizes). *)
Definition vacuous_internals_ok {cs: compspecs} (p: QP.program function) (G: funspecs) : bool :=
  forallb (fun ifd => match snd ifd with
                      | Internal f => @internal_static_ok cs f (vacuous_funspec (Internal f))
                      | External _ _ _ _ => true end)
          (filter (unspecified_internal G) (QPprog_funct p)).

Lemma internals_specified_vacuous p G: internals_specified p (G ++ vacuous_internals p G) = true.
Proof.
  unfold internals_specified. apply forallb_forall. intros [i [fd|v]] H; simpl; auto.
  destruct fd as [f|]; auto.
  rewrite map_app, id_in_list_app.
  destruct (id_in_list i (map fst G)) eqn:E; auto. simpl.
  apply id_in_list_true_i. unfold vacuous_internals. rewrite map_map. simpl.
  apply (in_map fst (filter (unspecified_internal G) (QPprog_funct p)) (i, Internal f)).
  apply filter_In. split.
  - apply In_QPprog_funct. apply PTree.elements_complete. exact H.
  - unfold unspecified_internal. simpl. rewrite E. reflexivity.
Qed.

Lemma entries_vacuous (Espec: OracleKind) (cs: compspecs) (p: QP.program function) (G G': funspecs):
  @vacuous_internals_ok cs p G = true ->
  Forall (entry_of_prog Espec cs p G') (vacuous_internals p G).
Proof.
  intros OKV. unfold vacuous_internals, vacuous_internals_ok in *.
  rewrite Forall_map, Forall_forall. intros [i fd] Hin.
  pose proof Hin as Hin'. apply filter_In in Hin'. destruct Hin' as [Hin1 Hu].
  rewrite forallb_forall in OKV. specialize (OKV _ Hin).
  unfold entry_of_prog; simpl.
  rewrite (proj1 (In_QPprog_funct p i fd) Hin1).
  destruct fd as [f|]; [ | unfold unspecified_internal in Hu; discriminate].
  simpl in OKV |- *. split; auto.
  destruct f; split3; [reflexivity | reflexivity | intros; apply semax_vacuous].
Qed.

(* harness_safe_of_entries, with G's internal functions specified by G and every other internal function
   of p vacuous.  ENTRIES is only about G; G' = G ++ vacuous_internals p G is the whole context. *)
Theorem harness_safe_of_specs (cs: compspecs) (p: QP.program function) (G: funspecs)
  (post: (ident -> val) -> environ -> mpred)
  (NOREP: compute_list_norepet
     (map fst (QP.prog_builtins p) ++ map fst (PTree.elements (QP.prog_defs p))) = true)
  (CE: QP.prog_comp_env p =
     QPcomposite_env_of_composite_env (@cenv_cs cs) (@ha_env_cs cs) (@la_env_cs cs))
  (CBC: cenv_built_correctly
     (map compdef_of_compenv_element (sort_rank (PTree.elements (QP.prog_comp_env p)) []))
     (@cenv_cs cs) = Errors.OK tt)
  (ALIGNED: QPall_initializers_aligned p = true)
  (EXT_OK: all_unspecified_OK p)
  (DNB: forallb not_builtin (PTree.elements (QP.prog_defs p)) = true)
  (FUNS_NOREP: compute_list_norepet (map fst (QPvarspecs p) ++
     map fst (prog_funct' (map of_builtin (QP.prog_builtins p)) ++ QPprog_funct p)) = true)
  (VG_NOREP: compute_list_norepet (map fst (QPvarspecs p) ++ map fst (G ++ vacuous_internals p G)) = true)
  (VACUOUS: @vacuous_internals_ok cs p G = true)
  (MAIN: find_id (QP.prog_main p) G = Some (QPmain_spec_ext' p tt post))
  (ENTRIES: Forall (entry_of_prog (@HonestEspec cs) cs p (G ++ vacuous_internals p G)) G):
  harness_safe p.
Proof.
  apply (harness_safe_of_entries cs p (G ++ vacuous_internals p G) post); auto.
  - apply internals_specified_vacuous.
  - rewrite find_id_app1 with (x := QPmain_spec_ext' p tt post); auto.
  - apply Forall_app. split; auto. apply entries_vacuous; auto.
Qed.

(* ---------------------------------------------------------------------- *)
(* Moving a body proof into a law's program                                *)
(* ---------------------------------------------------------------------- *)

(* Every function of G is in G' with a stronger specification (funspec_sub). *)
Definition ctx_sub (G G': funspecs) : Prop :=
  forall i phi, find_id i G = Some phi -> exists phi', find_id i G' = Some phi' /\ funspec_sub phi' phi.

Lemma funspec_sub_type: forall phi1 phi2, funspec_sub phi1 phi2 -> type_of_funspec phi1 = type_of_funspec phi2.
Proof.
  intros [sig1 cc1 A1 P1 Q1 P1ne Q1ne] [sig2 cc2 A2 P2 Q2 P2ne Q2ne] [[E1 E2] _].
  subst; reflexivity.
Qed.

Lemma ctx_sub_refl G: ctx_sub G G.
Proof. intros i phi E. exists phi; split; auto. apply funspec_sub_refl. Qed.

(* A body proved under (cs1, V1, G1) holds under (cs2, V2, G2). *)
Lemma semax_body_move {cs1 cs2: compspecs} (V1 V2: varspecs) (G1 G2: funspecs) f spec:
  @semax_body V1 G1 cs1 f spec ->
  cspecs_sub cs1 cs2 ->
  Forall (fun it : ident * type => complete_type (@cenv_cs cs1) (snd it) = true) (fn_vars f) ->
  Forall (fun x => find_id (fst x) V2 = Some (snd x)) V1 ->
  ctx_sub G1 G2 ->
  list_norepet (map fst V1 ++ map fst G1) ->
  list_norepet (map fst V2 ++ map fst G2) ->
  @semax_body V2 G2 cs2 f spec.
Proof.
  intros SB CSUB COMPLETE HV HG LNR1 LNR2.
  apply (@semax_body_cenv_sub cs1 cs2 CSUB) in SB; auto.
  eapply Component.semax_body_subsumespec; [apply SB | |].
  - intros i. rewrite !semax_prog.make_context_g_char by auto.
    rewrite !initial_world.make_tycontext_s_find_id.
    destruct (find_id i G1) as [phi|] eqn:E.
    + destruct (HG i phi E) as [phi' [E' S]]. rewrite E'. simpl.
      rewrite (funspec_sub_type _ _ S). reflexivity.
    + destruct (initial_world.find_id i V1) as [t|] eqn:EV; simpl; auto.
      rewrite Forall_forall in HV.
      assert (IN: In (i, t) V1) by (apply find_id_e; exact EV).
      specialize (HV _ IN). simpl in HV.
      destruct (find_id i G2) as [phi'|] eqn:E2.
      * exfalso. apply list_norepet_app in LNR2. destruct LNR2 as [_ [_ D]].
        apply (D i i); auto.
        -- apply find_id_In_map_fst in HV; auto.
        -- apply find_id_In_map_fst in E2; auto.
      * exact HV.
  - intros i. destruct (find_id i G1) as [phi|] eqn:E; [ | simpl; auto].
    destruct (HG i phi E) as [phi' [E' S]]. simpl. exists phi'. split; auto.
    rewrite funspec_sub_iff in S. exact (VST.veric.seplog.funspec_sub_sub_si _ _ S).
Qed.

(* ---------------------------------------------------------------------- *)
(* cspecs_sub by computation                                               *)
(* ---------------------------------------------------------------------- *)

Definition QPce (cs: compspecs) : QP.composite_env :=
  QPcomposite_env_of_composite_env (@cenv_cs cs) (@ha_env_cs cs) (@la_env_cs cs).

Definition QPsub_b (ce1 ce2: QP.composite_env) : bool :=
  forallb (fun ic => match PTree.get (fst ic) ce2 with Some d => QPcomposite_eq (snd ic) d | None => false end)
          (PTree.elements ce1).

Lemma QPsub_b_e ce1 ce2: QPsub_b ce1 ce2 = true -> PTree_sub ce1 ce2.
Proof.
  unfold QPsub_b, PTree_sub. intros H i.
  destruct (PTree.get i ce1) as [c|] eqn:E; simpl; auto.
  rewrite forallb_forall in H. specialize (H (i, c) (PTree.elements_correct _ _ E)). simpl in H.
  destruct (PTree.get i ce2) as [d|]; [ | discriminate].
  apply QPcomposite_eq_e in H. subst; auto.
Qed.

Lemma QPce_get (cs: compspecs) i:
  PTree.get i (QPce cs) =
  match PTree.get i (@cenv_cs cs), PTree.get i (@ha_env_cs cs), PTree.get i (@la_env_cs cs) with
  | Some c, Some h, Some l => Some (QPcomposite_of_composite c h l)
  | None, None, None => None
  | _, _, _ => None
  end.
Proof. unfold QPce, QPcomposite_env_of_composite_env. apply PTree_gmap3; [apply PTree_samedom_ha | apply PTree_samedom_la]. Qed.

Lemma QPce_some (cs: compspecs) i c:
  PTree.get i (@cenv_cs cs) = Some c ->
  exists h l, PTree.get i (@ha_env_cs cs) = Some h /\ PTree.get i (@la_env_cs cs) = Some l /\
              PTree.get i (QPce cs) = Some (QPcomposite_of_composite c h l).
Proof.
  intros E. rewrite QPce_get, E.
  destruct (proj1 (@ha_env_cs_complete cs i) (ex_intro _ c E)) as [h Eh].
  destruct (proj1 (@la_env_cs_complete cs i) (ex_intro _ c E)) as [l El].
  rewrite Eh, El. eauto.
Qed.

Lemma QPce_inv (cs: compspecs) i x:
  PTree.get i (QPce cs) = Some x ->
  exists c h l, PTree.get i (@cenv_cs cs) = Some c /\ PTree.get i (@ha_env_cs cs) = Some h /\
                PTree.get i (@la_env_cs cs) = Some l /\ x = QPcomposite_of_composite c h l.
Proof.
  rewrite QPce_get. intros E.
  destruct (PTree.get i (@cenv_cs cs)), (PTree.get i (@ha_env_cs cs)), (PTree.get i (@la_env_cs cs));
    inversion E; subst; eauto 7.
Qed.

Lemma QPcomposite_of_composite_inj c h l c' h' l':
  QPcomposite_of_composite c h l = QPcomposite_of_composite c' h' l' -> c = c' /\ h = h' /\ l = l'.
Proof.
  intros E.
  assert (h = h') by (apply (f_equal QP.co_ha) in E; exact E).
  assert (l = l') by (apply (f_equal QP.co_la) in E; exact E).
  split; auto.
  assert (OK: QPcomposite_OK (QPcomposite_of_composite c h l)) by apply QPcomposite_of_composite_OK.
  pose proof (composite_of_QPcomposite_of_composite c h l OK) as C1.
  assert (OK': QPcomposite_OK (QPcomposite_of_composite c' h' l')) by apply QPcomposite_of_composite_OK.
  pose proof (composite_of_QPcomposite_of_composite c' h' l' OK') as C2.
  revert OK C1. rewrite E. intros OK C1. rewrite <- C1, <- C2. f_equal. apply proof_irr.
Qed.

Lemma cspecs_sub_by_computation (cs1 cs2: compspecs):
  QPsub_b (QPce cs1) (QPce cs2) = true -> cspecs_sub cs1 cs2.
Proof.
  intros H. apply QPsub_b_e in H.
  assert (K: forall i c, PTree.get i (@cenv_cs cs1) = Some c ->
    exists h l, PTree.get i (@cenv_cs cs2) = Some c /\ PTree.get i (@ha_env_cs cs1) = Some h /\
      PTree.get i (@ha_env_cs cs2) = Some h /\ PTree.get i (@la_env_cs cs1) = Some l /\
      PTree.get i (@la_env_cs cs2) = Some l). {
    intros i c E. destruct (QPce_some cs1 i c E) as [h [l [Eh [El Eq]]]].
    specialize (H i). rewrite Eq in H. simpl in H.
    destruct (QPce_inv cs2 i _ H) as [c' [h' [l' [E' [Eh' [El' X]]]]]].
    apply QPcomposite_of_composite_inj in X. destruct X as [? [? ?]]; subst.
    exists h', l'; auto. }
  split3; intros i.
  - destruct (PTree.get i (@cenv_cs cs1)) as [c|] eqn:E; simpl; auto.
    destruct (K i c E) as [h [l [? _]]]; auto.
  - destruct (PTree.get i (@ha_env_cs cs1)) as [h|] eqn:Eh; simpl; auto.
    destruct (proj2 (@ha_env_cs_complete cs1 i) (ex_intro _ h Eh)) as [c E].
    destruct (K i c E) as [h' [l [_ [Eh1 [Eh2 _]]]]]. rewrite Eh in Eh1. inversion Eh1; subst; auto.
  - destruct (PTree.get i (@la_env_cs cs1)) as [l|] eqn:El; simpl; auto.
    destruct (proj2 (@la_env_cs_complete cs1 i) (ex_intro _ l El)) as [c E].
    destruct (K i c E) as [h [l' [_ [_ [_ [El1 El2]]]]]]. rewrite El in El1. inversion El1; subst; auto.
Qed.


(* ---------------------------------------------------------------------- *)
(* The environment's specifications at two compspecs                      *)
(* ---------------------------------------------------------------------- *)
(* A body proved under its unit's compspecs cs1 has the environment's specs at cs1 in its context; the law's
   G has them at the law's compspecs cs2.  nondet_u8/u32/size and gp_assert/assume do not depend on the
   compspecs (one term); malloc, free and nondet_bytes do: funspec_sub (spec at cs2) (spec at cs1) below,
   for cs1 a sub-environment of cs2 whose composites stay the same (PRES, decided by preserved_by_computation). *)

(* The change_composite_env of any two compspecs (VST's cs_preserve_env, not computed). *)
Definition CCE_any (cs1 cs2: compspecs) : change_composite_env cs1 cs2 :=
  {| coeq := cs_preserve_env cs1 cs2;
     coeq_consistent := cs_preserve_env_consistent cs1 cs2 _ eq_refl;
     coeq_complete := cs_preserve_completeness cs1 cs2 _ eq_refl |}.

Lemma data_at_tuchar_cs: forall (cs1 cs2: compspecs) sh n (v: list val) p,
  @data_at cs1 sh (tarray tuchar n) v p = @data_at cs2 sh (tarray tuchar n) v p.
Proof.
  intros.
  apply (f_equal (fun f => f p)).
  apply (@data_at_change_composite cs1 cs2 (CCE_any cs1 cs2)); [apply JMeq_refl | reflexivity].
Qed.

Lemma data_at__tuchar_cs: forall (cs1 cs2: compspecs) sh n p,
  @data_at_ cs1 sh (tarray tuchar n) p = @data_at_ cs2 sh (tarray tuchar n) p.
Proof.
  intros.
  apply (f_equal (fun f => f p)).
  apply (@data_at__change_composite cs1 cs2 (CCE_any cs1 cs2)); reflexivity.
Qed.

Lemma nondet_bytes_spec_cs: forall (cs1 cs2: compspecs),
  funspec_sub (snd (@nondet_bytes_spec cs2)) (snd (@nondet_bytes_spec cs1)).
Proof.
  intros. do_funspec_sub. destruct w as [[buf n] sh].
  Exists (buf, n, sh) emp. simpl. rewrite (data_at__tuchar_cs cs1 cs2).
  entailer!. intros. Exists x0. rewrite (data_at_tuchar_cs cs2 cs1). entailer!.
Qed.

Section MallocSub.
Variables cs1 cs2: compspecs.
Hypothesis CSUB: cspecs_sub cs1 cs2.
(* every complete type of cs1 keeps its composites in cs2 (proved by computation for concrete
   compspecs) *)
Hypothesis PRES: forall t, @complete_legal_cosu_type (@cenv_cs cs1) t = true ->
  cs_preserve_type cs1 cs2 (@coeq _ _ (CCE_any cs1 cs2)) t = true.

Lemma ha_preserve: forall t, @complete_legal_cosu_type (@cenv_cs cs1) t = true ->
  hardware_alignof (@ha_env_cs cs2) t = hardware_alignof (@ha_env_cs cs1) t.
Proof.
  destruct CSUB as [CE [HE LE]].
  induction t; simpl; intros H; auto; try discriminate;
  destruct (Maps.PTree.get i (@cenv_cs cs1)) as [co|] eqn:E; try discriminate;
  destruct (proj1 (@ha_env_cs_complete cs1 i) (ex_intro _ co E)) as [z Z1];
  specialize (HE i); rewrite Z1 in HE; simpl in HE; rewrite HE, Z1; reflexivity.
Qed.

Lemma la_preserve: forall t, @complete_legal_cosu_type (@cenv_cs cs1) t = true ->
  legal_alignas_type (@cenv_cs cs2) (@ha_env_cs cs2) (@la_env_cs cs2) t =
  legal_alignas_type (@cenv_cs cs1) (@ha_env_cs cs1) (@la_env_cs cs1) t.
Proof.
  induction t; intros H; auto; unfold legal_alignas_type in *; simpl in *.
  - rewrite (IHt H).
    change (@Ctypes.sizeof (@cenv_cs cs2) t) with (@sizeof cs2 t).
    change (@Ctypes.sizeof (@cenv_cs cs1) t) with (@sizeof cs1 t).
    rewrite <- (@sizeof_change_composite cs1 cs2 (CCE_any cs1 cs2) t (PRES t H)), (ha_preserve t H).
    reflexivity.
  - destruct CSUB as [CE [HE LE]].
    destruct (Maps.PTree.get i (@cenv_cs cs1)) as [co|] eqn:E; try discriminate.
    destruct (proj1 (@la_env_cs_complete cs1 i) (ex_intro _ co E)) as [z Z1].
    specialize (LE i). rewrite Z1 in LE. simpl in LE.
    assert (Z1': @Maps.PTree.get bool i (@la_env_cs cs1) = Some z) by exact Z1.
    assert (Z2': @Maps.PTree.get bool i (@la_env_cs cs2) = Some z) by exact LE.
    rewrite Z1', Z2'. reflexivity.
  - destruct CSUB as [CE [HE LE]].
    destruct (Maps.PTree.get i (@cenv_cs cs1)) as [co|] eqn:E; try discriminate.
    destruct (proj1 (@la_env_cs_complete cs1 i) (ex_intro _ co E)) as [z Z1].
    specialize (LE i). rewrite Z1 in LE. simpl in LE.
    assert (Z1': @Maps.PTree.get bool i (@la_env_cs cs1) = Some z) by exact Z1.
    assert (Z2': @Maps.PTree.get bool i (@la_env_cs cs2) = Some z) by exact LE.
    rewrite Z1', Z2'. reflexivity.
Qed.

Lemma natural_aligned_preserve: forall na t, @complete_legal_cosu_type (@cenv_cs cs1) t = true ->
  @natural_aligned cs2 na t = @natural_aligned cs1 na t.
Proof.
  intros. unfold natural_aligned, is_aligned. rewrite (ha_preserve t H), (la_preserve t H).
  reflexivity.
Qed.

Lemma malloc_spec'_sub: funspec_sub (@malloc_spec' cs2) (@malloc_spec' cs1).
Proof.
  do_funspec_sub. destruct w as [t gv]. Exists (t, gv) emp. simpl. Intros.
  pose proof (PRES t H1) as P.
  pose proof (@sizeof_change_composite cs1 cs2 (CCE_any cs1 cs2) t P) as S.
  pose proof (@complete_legal_cosu_type_change_composite cs1 cs2 (CCE_any cs1 cs2) t P) as C.
  pose proof (natural_aligned_preserve natural_alignment t H1) as N.
  pose proof (@malloc_token_change_composite cs1 cs2 (CCE_any cs1 cs2) Ews t P) as MT.
  pose proof (@data_at__change_composite cs1 cs2 (CCE_any cs1 cs2) Ews t P) as DT.
  rewrite <- S, N, <- C, <- MT, <- DT.
  apply andp_right; [ apply prop_right | cancel ].
  split; [ | split; [repeat split; auto | split; auto ] ].
  2,3: lia.
  intros rho. apply andp_left2. rewrite emp_sepcon. apply derives_refl.
Qed.

Lemma free_spec'_sub: funspec_sub (@free_spec' cs2) (@free_spec' cs1).
Proof.
  do_funspec_sub. destruct w as [[t p] gv]. Exists (t, p, gv) emp. simpl. Intros.
  destruct (EqDec_val p nullval).
  - entailer!.
  - assert_PROP (@field_compatible cs1 t [] p) as FC by (rewrite data_at__memory_block; entailer!).
    destruct FC as [_ [HC _]].
    pose proof (PRES t HC) as P.
    pose proof (@malloc_token_change_composite cs1 cs2 (CCE_any cs1 cs2) Ews t P) as MT.
    pose proof (@data_at__change_composite cs1 cs2 (CCE_any cs1 cs2) Ews t P) as DT.
    rewrite MT, DT. apply andp_right; [apply prop_right | cancel].
    split; auto. intros rho. apply andp_left2. rewrite emp_sepcon. apply derives_refl.
Qed.
End MallocSub.


(* PRES of the section above, by computation: every composite of cs1 is preserved in cs2. *)
Definition preserved_b (cs1 cs2: compspecs) : bool :=
  forallb (fun ic => match PTree.get (fst ic) (@coeq _ _ (CCE_any cs1 cs2)) with
                     | Some b => test_aux cs1 cs2 b (fst ic)
                     | None => false end)
          (PTree.elements (@cenv_cs cs1)).

Lemma preserved_by_computation (cs1 cs2: compspecs):
  preserved_b cs1 cs2 = true ->
  forall t, @complete_legal_cosu_type (@cenv_cs cs1) t = true ->
  cs_preserve_type cs1 cs2 (@coeq _ _ (CCE_any cs1 cs2)) t = true.
Proof.
  intros H. unfold preserved_b in H. rewrite forallb_forall in H.
  assert (K: forall i co, PTree.get i (@cenv_cs cs1) = Some co ->
             match PTree.get i (@coeq _ _ (CCE_any cs1 cs2)) with
             | Some b => test_aux cs1 cs2 b i | None => false end = true). {
    intros i co E. exact (H (i, co) (PTree.elements_correct _ _ E)). }
  induction t; intros C; simpl in *; auto;
    destruct (PTree.get i (@cenv_cs cs1)) as [co|] eqn:E; try discriminate; exact (K i co E).
Qed.

(* ---------------------------------------------------------------------- *)
(* One entry of a law's G from a shared body proof                         *)
(* ---------------------------------------------------------------------- *)

Definition complete_vars_b (cs: compspecs) (f: function) : bool :=
  forallb (fun it : ident * type => complete_type (@cenv_cs cs) (snd it)) (fn_vars f).

(* The entry (i, phi) of a law's G (program p, compspecs cs) from the body proof of f under its own
   compspecs cs1 and context (V1, G1): every condition but the context inclusion (CTX) is computed. *)
Lemma entry_moved (Espec: OracleKind) (cs cs1: compspecs) (p: QP.program function) (G: funspecs)
    (V1: varspecs) (G1: funspecs) (i: ident) (phi: funspec) (f: function) :
  @semax_body V1 G1 cs1 f (i, phi) ->
  PTree.get i (QP.prog_defs p) = Some (Gfun (Internal f)) ->
  @internal_static_ok cs f phi = true ->
  QPsub_b (QPce cs1) (QPce cs) = true ->
  complete_vars_b cs1 f = true ->
  Forall (fun x => find_id (fst x) (QPvarspecs p) = Some (snd x)) V1 ->
  compute_list_norepet (map fst V1 ++ map fst G1) = true ->
  compute_list_norepet (map fst (QPvarspecs p) ++ map fst G) = true ->
  ctx_sub G1 G ->
  entry_of_prog Espec cs p G (i, phi).
Proof.
  intros B GET S CSUB VARS V LNR1 LNR CTX.
  apply (entry_internal_intro Espec cs p G (i, phi) f GET S).
  apply (semax_body_move V1 (QPvarspecs p) G1 G f (i, phi) B); auto.
  - apply cspecs_sub_by_computation; auto.
  - unfold complete_vars_b in VARS. rewrite forallb_forall in VARS. rewrite Forall_forall. auto.
  - apply compute_list_norepet_e; auto.
  - apply compute_list_norepet_e; auto.
Qed.

(* ctx_sub G1 G for concrete lists: each entry of G1 is in G with the same specification, or with one the
   environment's transport lemmas relate (malloc, free, nondet_bytes at another compspecs). *)
Ltac env_spec_sub :=
  first [ apply funspec_sub_refl
        | apply nondet_bytes_spec_cs
        | apply malloc_spec'_sub;
          [ apply cspecs_sub_by_computation; vm_compute; reflexivity
          | apply preserved_by_computation; vm_compute; reflexivity ]
        | apply free_spec'_sub;
          [ apply cspecs_sub_by_computation; vm_compute; reflexivity
          | apply preserved_by_computation; vm_compute; reflexivity ] ].

Ltac ctx_sub_tac :=
  let i := fresh "i" in let phi := fresh "phi" in let E := fresh "E" in
  intros i phi E; simpl in E;
  repeat (if_tac in E; [ inv E; eexists; split; [ reflexivity | env_spec_sub ] | ]);
  try discriminate.

(* Goal Forall (entry_of_prog Espec cs p G) (spec :: rest): the head entry from the shared body proof B
   (semax_body V1 G1 f spec under its own compspecs); leaves Forall ... rest. *)
Ltac entry_shared B :=
  lazymatch type of B with
  | @semax_body _ _ ?cs1 ?f ?spec =>
    apply Forall_cons;
    [ eapply (entry_moved _ _ cs1 _ _ _ _ (fst spec) (snd spec) f B);
      [ reflexivity | vm_compute; reflexivity | vm_compute; reflexivity | vm_compute; reflexivity
      | find_ids_V | vm_compute; reflexivity | vm_compute; reflexivity | ctx_sub_tac ]
    | ]
  end.

(* ---------------------------------------------------------------------- *)
(* main                                                                    *)
(* ---------------------------------------------------------------------- *)

(* The postcondition of main in harness_safe is free: TT. *)
Definition main_post_TT : (ident -> val) -> environ -> mpred := fun _ _ => TT.

(* main's specification in the canonical form start_function expects: the program's global variables
   (globvars2pred) and the external state, any int result. *)
Definition main_spec_std (p: QP.program function) : funspec :=
  WITH gv: globals
  PRE [] PROP () PARAMS () GLOBALS (gv) SEP (globvars2pred gv (QPprog_vars p); has_ext tt)
  POST [ tint ] EX r: int, PROP () RETURN (Vint r) SEP (TT).

Lemma main_spec_std_sub (p: QP.program function):
  funspec_sub (main_spec_std p) (QPmain_spec_ext' p tt main_post_TT).
Proof.
  unfold QPmain_spec_ext', main_spec_std. do_funspec_sub. unfold main_pre. simpl.
  Intros. subst w args.
  Exists (initialize.genviron2globals g) emp. rewrite emp_sepcon.
  apply andp_right; [ | apply prop_right; intros; unfold main_post_TT; apply TT_right ].
  apply andp_right; [ apply TT_right | ].
  apply andp_right; [ apply prop_right; reflexivity | ].
  apply andp_right; [ apply prop_right; split; auto | apply derives_refl ].
  unfold gvars_denote. simpl. intros. reflexivity.
Qed.

(* The composites of a QP program in the order of harness_safe (to build a law's compspecs with
   make_compspecs, after vm_compute). *)
Definition prog_composites (p: QP.program function) : list composite_definition :=
  map compdef_of_compenv_element (sort_rank (PTree.elements (QP.prog_comp_env p)) []).

(* Goal harness_safe p: harness_safe_of_specs with compspecs cs, specs G and main's postcondition post;
   the computable side conditions are discharged.  Leaves MAIN and ENTRIES (one entry_shared /
   entry_internal / entry_external per element of G, then Forall_nil). *)
Ltac harness_safe_by_specs cs G post :=
  apply (harness_safe_of_specs cs _ G post);
  [ vm_compute; reflexivity
  | vm_compute; reflexivity
  | vm_compute; reflexivity
  | vm_compute; reflexivity
  | red; vm_compute; reflexivity
  | vm_compute; reflexivity
  | vm_compute; reflexivity
  | vm_compute; reflexivity
  | vm_compute; reflexivity
  | | ].

(* A body of main proved with main_spec_std is a body of harness_safe's main. *)
Lemma semax_body_main_std {cs: compspecs} (V: varspecs) (G: funspecs) (p: QP.program function) (i: ident) f:
  @semax_body V G cs f (i, main_spec_std p) ->
  compute_list_norepet (map fst (fn_params f) ++ map fst (fn_temps f)) = true ->
  @semax_body V G cs f (i, QPmain_spec_ext' p tt main_post_TT).
Proof.
  intros B LNR. eapply semax_body_funspec_sub; [exact B | apply main_spec_std_sub | ].
  apply compute_list_norepet_e; exact LNR.
Qed.
