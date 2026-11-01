# Writing specs

A spec states the claim as a C program you can run. Its file goes in the project's `harness/` directory, and `qp`
calls it a law. The proof answers exactly the question the spec asks, and "no counterexample found" means none for
the calls this spec makes. A weak spec gives a theorem that is true and proved but says little. A person reads every
spec, whoever wrote it. It checks results with `qp_assert` and restricts its inputs with `qp_assume`; older specs
write `gp_assert` and `gp_assume`, the functions these two stand for, and tools that run a spec report those names.

## One library, two specs

Our work on the lz4 decoder, not published yet, had two specs. Spec 1, which was proved, calls only
`LZ4_decompress_safe`, with any compressed bytes, any output capacity and only the true sizes. It allocates
`n + 1` input bytes so that `malloc(0)` is never called. Spec 2 calls each decoding entry point a client may
call, with every size a caller can pass, and allocates every buffer exactly.

A proof of spec 1 says nothing about the partial decoder, the dictionary entry points or the sizes a careless
caller may pass, and its `n + 1` allocation would have hidden a one-byte overread of the input, had there been
one. On lz4 as it was in 2021, before the fix of CVE-2021-3520, agents that were not told about the bug found
that CVE with spec 2. That run is not published.

## Rules

1. Cover the whole API contract: every entry point a client may call, in any order the API allows, with every
   argument a caller can pass, including invalid ones (negative sizes, NULL, zero, maximum values). Where the
   documentation says "the caller must", decide whether the claim includes misuse, and say so in the spec's
   comment.
2. Allocate exactly the size of the contents (`malloc(n)`, also for `n == 0`). A slack byte hides one-byte
   overreads, a common bug.
3. Say what a correct result is: a round trip, a prefix property, an exact return value, bounds on sizes,
   counters never above what was offered, a reset state equal to a fresh one. Memory safety comes with every
   functional check.
4. Bounded sizes are fine, since the proof is symbolic below the bound. So are unbounded loops of calls
   (partial correctness), but make sure the checks are reachable. A spec that returns early on most paths
   proves little.
5. Run `qp check` before proving ([docs/QP.md](QP.md)). Native runs under ASan and UBSan (`qp fuzz`) must be
   clean or show a real bug. Mutants (`qp mutants`) are broken versions of the code under test, such as a
   removed bounds check or an inverted comparison. A spec that notices none of them is not worth a proof. A
   stop under CompCert's interpreter (`qp interp`) is a real defect or an idiom to patch
   ([docs/RECIPE.md](RECIPE.md), step 3).
6. Write one property and one theorem per spec, and prove a project's theorems together, so that the
   function specifications are shared and strong enough for all.
7. Initialise the spec's globals in `main`. CompCert's interpreter runs all seeds in one process
   (`runtime/interp_driver.c`), so a global left over from the previous seed gives false stops.
8. End the last case of every `switch` with `break`. VST's only switch rule gives a case that falls off the end
   the postcondition `FF`, so such a switch cannot be proved although CompCert defines it (for example a
   `default: { ... }` without `break`). Code under test with one needs an idiom patch. `qp lint` finds them.
9. Tell whoever does the proof that the property may be false, and ask for a counterexample when stuck.
10. An assume that no input can satisfy makes every later `qp_assert` provable and the spec useless. Such
    a spec notices no mutant, and the gate below catches it sooner.

## The non-vacuity gate

`tools/fuzz_gate.sh HARNESS.c [RUNS [BUDGET [TIMEOUT]]] [-- extra cc args]` builds the spec with
`runtime/fuzz_driver.c` and runs it in gate mode (`GP_GATE=1`). Per call site (the caller's return address),
the driver counts how often each `qp_assume` was reached and let the input through, and how often each
`qp_assert` was reached by an input that passed the assumes before it. The counts of all forked runs add up in
shared memory. It also prints how many runs passed every assume they reached (`completed`) and how many did not
(`rejected`), and a verdict:

```
gp_assume sites: 1
  assume #0 @0x..: passed 371/500 (74.2%)
gp_assert sites: 2
  assert #0 @0x..: reached 371
  assert #1 @0x..: reached 371
non-vacuity gate: PASS (ok)
```

The gate fails when a reached `qp_assume` lets no input through, or when no `qp_assert` is reached.
`qp_assume(0)` fails it at once. So does an assume that the random inputs never satisfy in `RUNS` draws; then
use more runs, or a project `nondet_*` (an `env.c`, [docs/QP.md](QP.md)) that draws from the assumed range more
often.

A proved theorem does not depend on the gate, and the gate cannot tell a weak spec. Whether an assume
excludes only real misuse, and nothing the property should cover, is for the reviewer (rule 1). Like any
test, the gate sees only the sites it reaches: an assert that is unreachable for another reason is invisible
to it.
