(* QuickProof.Link: what the honest environment does with an external function that is not one of its own,
   and the check that per-law contracts make on their linked program.

   Not trusted: definitions and proofs, no axiom.  Used by the contracts of per-law linking
   (quickproof.conf LINK=per-law, docs/LINKING.md).

   - honest_rejects_foreign: HonestEspec (QuickProof.Env) gives an external function a witness type, hence a
     specification that a call can satisfy, only when its name and signature are those of a function of
     env_specs.  For every other external function -- a function declared and not defined by the linked
     program, under any name -- the witness type is empty (VST's NullExtension), so no call of it is safe:
     a program proved in this world never calls it.  The environment never treats an unknown external as
     honest.
   - undefined_globals p: the globals that the program p declares without defining, except the
     environment's functions with the environment's signatures: external functions (EF_external) of any
     other name or signature, and variables without an initialiser.  A per-law contract states the list
     it expects (Lemma whole_prog_undefined) and Coq checks it by computation when the contract is built: a
     global that the per-law program should define (because some unit of the project defines it) and does
     not, makes the contract fail to build. *)
From Coq Require Import String List.
Require Import VST.floyd.proofauto.
Require Import VST.floyd.VSU.
Require Import VST.sepcomp.extspec.
Require Import VST.veric.semax_ext.
Require Import QuickProof.Env.
Import ListNotations.
Local Open Scope string_scope.

(* The functions of env_specs, by name and CompCert signature (env_signatures_spec: exactly env_specs, so a
   change of Env.v breaks this file until the list follows; tools/link_units.py's ENV must list the same names,
   checked by tests/run.sh). *)
Definition env_signatures : list (string * signature) :=
  [ ("quickproof_malloc", mksignature (AST.Xlong :: nil) AST.Xptr cc_default);
    ("quickproof_free", mksignature (AST.Xptr :: nil) AST.Xvoid cc_default);
    ("nondet_u8", mksignature nil AST.Xint8unsigned cc_default);
    ("nondet_u32", mksignature nil AST.Xint cc_default);
    ("nondet_size", mksignature nil AST.Xlong cc_default);
    ("nondet_bytes", mksignature (AST.Xptr :: AST.Xlong :: nil) AST.Xvoid cc_default);
    ("gp_assert", mksignature (AST.Xint :: nil) AST.Xvoid cc_default);
    ("gp_assume", mksignature (AST.Xint :: nil) AST.Xvoid cc_default) ].

Definition sig_of_spec (phi: funspec) : signature :=
  typesig2signature (typesig_of_funspec phi) (callingconvention_of_funspec phi).

Lemma env_signatures_spec {cs: compspecs} :
  map (fun ip => (fst ip, sig_of_spec (snd ip))) (@env_specs cs) =
  map (fun ns => (env_link (fst ns), snd ns)) env_signatures.
Proof. reflexivity. Qed.

(* ef is a function of the environment: its identifier (env_link of its name) and its signature are those
   of an entry of env_specs.  This is what add_funspecs (HonestEspec) matches on. *)
Definition is_env_function (ef: external_function) : bool :=
  match ef with
  | EF_external name sg =>
      existsb (fun ns => andb (Pos.eqb (env_link (fst ns)) (env_link name)) (eqb_signature (snd ns) sg))
              env_signatures
  | _ => false
  end.

Lemma eqb_signature_refl: forall s, eqb_signature s s = true.
Proof.
  intros [args res cc]; simpl.
  rewrite eqb_list_refl by apply eqb_xtype_refl.
  rewrite eqb_xtype_refl. simpl. apply eqb_calling_convention_refl.
Qed.

Theorem honest_rejects_foreign {cs: compspecs} (ef: external_function) :
  is_env_function ef = false ->
  ext_spec_type (@OK_spec (@HonestEspec cs)) ef -> False.
Proof.
  intros NOT.
  unfold HonestEspec, add_funspecs, NullExtension.Espec, env_specs; simpl.
  repeat (destruct (oi_eq_dec _ _) as [E|_];
          [ destruct ef; simpl in E; try discriminate E; injection E as E1 E2;
            unfold is_env_function in NOT; rewrite <- E1, <- E2 in NOT; vm_compute in NOT; discriminate NOT
          | ]).
  intro H; exact H.
Qed.

(* The globals p declares without defining, except the environment's functions. *)
Definition undefined_globals (p: QP.program function) : list ident :=
  map fst (filter (fun ig => match snd ig with
                             | Gfun (External ef _ _ _) => negb (is_env_function ef)
                             | Gfun (Internal _) => false
                             | Gvar v => match gvar_init v with nil => true | _ => false end
                             end)
                  (Maps.PTree.elements (QP.prog_defs p))).

Definition same_idents (l1 l2: list ident) : bool :=
  andb (forallb (fun i => existsb (Pos.eqb i) l2) l1) (forallb (fun i => existsb (Pos.eqb i) l1) l2).

(* p declares without defining exactly the globals named in `names` (and the environment's functions). *)
Definition undefined_globals_are (p: QP.program function) (names: list string) : bool :=
  same_idents (undefined_globals p) (map env_link names).
