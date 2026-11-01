(* QuickProof.Contract: the shape of every harness theorem.

   TRUSTED (with include/quickproof.h and QuickProof.Env).  Taken from an earlier proof, where it is written
   out for one program; here the program is a parameter.

   harness_safe p: VST's whole-program safety judgement semax_prog for the linked program p (the
   harness `main` + the code under test, as a QP.program), in the external world HonestEspec.
   semax_prog fixes main's precondition (main_pre) and leaves its postcondition free.  By VST's
   adequacy: no execution of p has undefined behaviour, for every behaviour of the externals that
   their specifications (QuickProof.Env) allow.  A harness executes undefined behaviour exactly when
   a check fails, so the theorem says the checks hold in every execution. *)
Require Import VST.floyd.proofauto.
Require Import VST.floyd.VSU.
Require Export QuickProof.Env.

Definition harness_safe (p: QP.program Clight.function) : Prop :=
  exists (cs: compspecs)
         (OK: QPprogram_OK p)
         (CBC: build_composite_env
                 (map compdef_of_compenv_element
                    (sort_rank (Maps.PTree.elements (QP.prog_comp_env p)) []))
               = Errors.OK
                   (composite_env_of_QPcomposite_env
                      (QP.prog_comp_env p) (projT1 (proj2 OK))))
         (G: funspecs),
    @semax_prog (@HonestEspec cs) cs
      (wholeprog_of_QPprog p OK CBC)
      tt (QPvarspecs p) G.
