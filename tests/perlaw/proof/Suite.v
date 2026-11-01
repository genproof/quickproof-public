(* The toy suite: both laws, each on its own per-law program, from one shared library. *)
Require Import QuickProof.Contract.
Require Toy.contracts.law_count Toy.contracts.law_pair.
Require Toy.proof.LawCount Toy.proof.LawPair.

Theorem suite :
  harness_safe Toy.contracts.law_count.whole_prog /\ harness_safe Toy.contracts.law_pair.whole_prog.
Proof. split; [exact Toy.proof.LawCount.law_count_proved | exact Toy.proof.LawPair.law_pair_proved]. Qed.

Print Assumptions suite.
