(* QuickProof.Env: the external world of every harness theorem.

   TRUSTED (with include/quickproof.h and QuickProof.Contract).  Taken from an earlier proof and made
   program-independent: identifiers are the `$"name"` identifiers clightgen gives every unit, so env_link is
   ident_of_string.

   The world is VST's NullExtension extended (add_funspecs) with exactly these specifications:
   - nondet_u8/u32/size/bytes (include/quickproof.h): may return any value;
   - quickproof_malloc/quickproof_free: VST's standard malloc_spec'/free_spec'.  Code is built with
     -Dmalloc=quickproof_malloc -Dfree=quickproof_free (tools/clight.sh), so both are plain externals
     (add_funspecs covers only EF_external, not CompCert's EF_malloc/EF_free).
   Their bodies are proved in QuickProof.EnvBodies with VST's semax_ext: no environment axiom.
   (A theorem stated in NullExtension.Espec with axiomatised bodies is unsound: False is derivable.) *)
From Coq Require Import String.
Require Import VST.floyd.proofauto.
Require Import VST.floyd.library.
From compcert Require Import Clightdefs.
Import Clightdefs.ClightNotations.
Local Open Scope string_scope.
Local Open Scope clight_scope.

Definition _nondet_u8 : ident := $"nondet_u8".
Definition _nondet_u32 : ident := $"nondet_u32".
Definition _nondet_size : ident := $"nondet_size".
Definition _nondet_bytes : ident := $"nondet_bytes".
Definition _quickproof_malloc : ident := $"quickproof_malloc".
Definition _quickproof_free : ident := $"quickproof_free".
Definition _gp_assert : ident := $"gp_assert".
Definition _gp_assume : ident := $"gp_assume".

Section Environment.
Context {CS: compspecs}.

Definition nondet_u8_spec :=
  DECLARE _nondet_u8
  WITH u: unit
  PRE  [ ] PROP () PARAMS () SEP ()
  POST [ tuchar ] EX b: Z,
       PROP (0 <= b <= Byte.max_unsigned) RETURN (Vint (Int.repr b)) SEP ().

Definition nondet_u32_spec :=
  DECLARE _nondet_u32
  WITH u: unit
  PRE  [ ] PROP () PARAMS () SEP ()
  POST [ tuint ] EX n: Z,
       PROP (0 <= n <= Int.max_unsigned) RETURN (Vint (Int.repr n)) SEP ().

Definition nondet_size_spec :=
  DECLARE _nondet_size
  WITH u: unit
  PRE  [ ] PROP () PARAMS () SEP ()
  POST [ tulong ] EX n: Z,
       PROP (0 <= n <= Int64.max_unsigned) RETURN (Vlong (Int64.repr n)) SEP ().

(* nondet_bytes(buf, n): buf must be writable for n bytes; afterwards it holds n arbitrary bytes.
   Any share and any prior contents.  buf may be NULL when n = 0 (malloc(0) may return NULL, and a
   harness passes that buffer on): the drivers access buf only for i < n. *)
Definition nondet_bytes_spec :=
  DECLARE _nondet_bytes
  WITH buf: val, n: Z, sh: share
  PRE  [ tptr tuchar, tulong ]
       PROP (writable_share sh; 0 <= n <= Int64.max_unsigned)
       PARAMS (buf; Vlong (Int64.repr n))
       SEP (if eq_dec buf nullval then !! (n = 0) && emp
            else data_at_ sh (tarray tuchar n) buf)
  POST [ tvoid ] EX bs: list Z,
       PROP (Zlength bs = n; Forall (fun b => 0 <= b <= Byte.max_unsigned) bs)
       RETURN ()
       SEP (if eq_dec buf nullval then emp
            else data_at sh (tarray tuchar n) (map (fun b => Vint (Int.repr b)) bs) buf).

(* gp_assert(c): the harness's check.  Its PREcondition c <> 0 is a proof obligation at every call
   site, so a proved harness never calls it with a false condition -- exactly an assertion.  Sound
   because a real function satisfies this spec: gp_assert stores through a null pointer when c = 0
   and returns otherwise, so it returns exactly when c <> 0 (the precondition) with no obligation. *)
Definition gp_assert_spec :=
  DECLARE _gp_assert
  WITH c: int
  PRE  [ tint ] PROP (c <> Int.zero) PARAMS (Vint c) SEP ()
  POST [ tvoid ] PROP () RETURN () SEP ().

(* gp_assume(c): restrict the run to inputs with c <> 0.  Its POSTcondition hands c <> 0 to the
   proof after the call.  Sound because a real function satisfies this spec:
   `void gp_assume(int c){ if(!c) for(;;){} }` returns with c <> 0, and when c = 0 never returns, so
   the postcondition holds vacuously.  Note gp_assume(0) yields False and makes everything after it
   provable; that is sound (the point is unreachable) but vacuous, so a harness's assumes are a
   review item (see docs/HARNESSES.md). *)
Definition gp_assume_spec :=
  DECLARE _gp_assume
  WITH c: int
  PRE  [ tint ] PROP () PARAMS (Vint c) SEP ()
  POST [ tvoid ] PROP (c <> Int.zero) RETURN () SEP ().

(* Every function of the external world, with its specification. *)
Definition env_specs : funspecs :=
  [ (_quickproof_malloc, malloc_spec'); (_quickproof_free, free_spec');
    nondet_u8_spec; nondet_u32_spec; nondet_size_spec; nondet_bytes_spec;
    gp_assert_spec; gp_assume_spec ].

End Environment.

(* External names -> identifiers: every unit uses the same $"name" identifiers. *)
Definition env_link (s: string) : ident := ident_of_string s.

(* The external world of the theorem. *)
Definition HonestEspec {CS: compspecs} : OracleKind :=
  add_funspecs NullExtension.Espec env_link env_specs.
