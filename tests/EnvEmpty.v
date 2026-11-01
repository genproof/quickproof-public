(* Regression: an empty NULL call is legal and preserves an unrelated cell. *)
From Coq Require Import String.
Require Import VST.floyd.proofauto.
Require Import QuickProof.Env.
From compcert Require Import Clightdefs.
Import Clightdefs.ClightNotations.
Local Open Scope string_scope.
Local Open Scope clight_scope.

Definition f_empty_probe : function := {|
  fn_return := tvoid; fn_callconv := cc_default; fn_params := nil;
  fn_vars := nil; fn_temps := nil;
  fn_body := Ssequence
    (Scall None
      (Evar _nondet_bytes (Tfunction ((tptr tuchar) :: tulong :: nil) tvoid cc_default))
      ((Ecast (Econst_int (Int.repr 0) tint) (tptr tuchar)) ::
       (Econst_long (Int64.repr 0) tulong) :: nil))
    (Sreturn None)
|}.

Definition f_nonnull_probe : function := {|
  fn_return := tvoid; fn_callconv := cc_default;
  fn_params := ((1%positive, tptr tuchar) :: (2%positive, tulong) :: nil);
  fn_vars := nil; fn_temps := nil;
  fn_body := Ssequence
    (Scall None
      (Evar _nondet_bytes (Tfunction ((tptr tuchar) :: tulong :: nil) tvoid cc_default))
      ((Etempvar 1%positive (tptr tuchar)) :: (Etempvar 2%positive tulong) :: nil))
    (Sreturn None)
|}.

Section Tests.
Context {CS: compspecs}.
Local Instance Espec : OracleKind := HonestEspec.

Definition empty_probe_spec :=
  DECLARE $"empty_probe"
  WITH p: val
  PRE [ ] PROP () PARAMS () SEP (data_at Tsh tint (Vint (Int.repr 42)) p)
  POST [ tvoid ] PROP () RETURN () SEP (data_at Tsh tint (Vint (Int.repr 42)) p).

Lemma empty_null_call_preserves_frame :
  semax_body nil [nondet_bytes_spec; empty_probe_spec] f_empty_probe empty_probe_spec.
Proof.
  start_function.
  forward_call (nullval, 0, Tsh).
  { simpl; entailer!. }
  Intros bs.
  forward.
Qed.

Definition nonnull_probe_spec :=
  DECLARE $"nonnull_probe"
  WITH buf: val, n: Z, p: val
  PRE [tptr tuchar, tulong]
    PROP (isptr buf; 0 <= n <= Int64.max_unsigned)
    PARAMS (buf; Vlong (Int64.repr n))
    SEP (data_at_ Tsh (tarray tuchar n) buf; data_at Tsh tint (Vint (Int.repr 42)) p)
  POST [tvoid] EX bs: list Z,
    PROP (Zlength bs = n; Forall (fun b => 0 <= b <= Byte.max_unsigned) bs)
    RETURN ()
    SEP (data_at Tsh (tarray tuchar n) (map (fun b => Vint (Int.repr b)) bs) buf;
         data_at Tsh tint (Vint (Int.repr 42)) p).

Lemma nonnull_call_preserves_contract_and_frame :
  semax_body nil [nondet_bytes_spec; nonnull_probe_spec] f_nonnull_probe nonnull_probe_spec.
Proof.
  start_function.
  assert_PROP (buf <> nullval) as Hnonnull by entailer!.
  forward_call (buf, n, Tsh).
  { if_tac; [contradiction | entailer!]. }
  Intros bs.
  if_tac; [contradiction |].
  forward.
  Exists bs; entailer!.
Qed.

End Tests.
Print Assumptions empty_null_call_preserves_frame.
Print Assumptions nonnull_call_preserves_contract_and_frame.
