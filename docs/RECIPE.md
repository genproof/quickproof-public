# Recipe: from an upstream repository to a checked proof

This page takes a small project through `tools/qp` ([QP.md](QP.md)). Below, `qp` is `tools/qp` of a checkout of
this repository: put `tools/` in your `PATH` or use the full path. `qp` needs the toolchain and tools that
[QP.md](QP.md) lists. Steps marked "(person)" are a person's decisions or reviews.

The upstream is a git repository holding the library of `examples/find_byte` (`mylib.c` and `mylib.h`, with one
function, `find_byte`), tagged `v1.0`. Make it next to the workspace:

```sh
mkdir mylib && cp quickproof/examples/find_byte/mylib.[ch] mylib/
(cd mylib && git init -q && git add . && git commit -qm v1.0 && git tag v1.0)
```

## 1. The project (`qp new`)

```sh
mkdir -p ws/projects && cd ws
qp new mylib "$PWD/../mylib"        # a real project gives the URL of its repository; --ref picks the commit
```

```
created .../ws/projects/mylib: upstream ... at v1.0 (bb0f4f47ec0c), framework ...
next: CODE/PATCH in project.conf, UNITS in quickproof.conf, laws in harness/, then `qp check mylib`
```

`qp new` pins the upstream to its latest release tag (here `v1.0`) and the framework to the commit of your
checkout. It writes `projects/mylib/project.conf` (the pins, `LOGICAL` and `CODE`), `quickproof.conf` (the units,
with the upstream's `.c` files listed as comments), `harness/` and `STATUS.md`. [QP.md](QP.md) describes every
field.

(person) Choose the units and the configuration. Here, uncomment `"mylib.c=src/mylib"` in `quickproof.conf`, and
set `CODE="mylib.c mylib.h"` in `project.conf`, with `LOGICAL=Demo` only so that the example's proof files fit
unchanged in step 6. Many libraries have build switches that avoid constructs VST cannot handle (step 3); prefer a
switch, set in `DEFS` of `quickproof.conf`, to an edit of the code. [SCOPE.md](SCOPE.md) says which code fits.

## 2. The properties (person)

Each property is stated by a spec, one C file in `projects/mylib/harness/`, which `qp` calls a law. Its `main`
draws the input from `quickproof.h` (`nondet_size()`, `nondet_u8()`, `nondet_bytes(buf, n)`, `pick(x)`),
restricts it with `qp_assume`, calls the library and states the property with `qp_assert`. Here it is
`examples/find_byte/harness/find_byte_ok.c`: for every buffer of up to 1 KiB and every byte `c`, `find_byte`
returns an index `r <= n`, and when `r < n`, `buf[r] == c`.

The theorem states exactly this program, so read it with care, whoever wrote it. [HARNESSES.md](HARNESSES.md)
describes what makes a spec worth proving. In short, cover the whole API, including invalid arguments, use exact
buffer sizes, and say what a correct result is.

## 3. Can VST take the code? (`qp tree`, `qp lint`, `qp audit`)

`qp tree mylib` makes the code under test (the upstream at the pinned commit, the project's files, the idiom patch
if there is one, and `quickproof/`) and prints its path. `qp lint mylib` looks for defined C that VST cannot
prove, such as a `switch` whose last case falls off its end, bitfields, and units that `clightgen` cannot
translate. `qp audit mylib` reads the Clight of each spec's cone, the functions the spec can reach:

```
cones: find_byte_ok 2 functions

BLOCKERS (not provable as is):
  none

review items (over the union of the cones: occurrences, then per function):
  narrowing cast                                       1  find_byte:1
  pointer arithmetic pointer-int                       2  find_byte:1, main:1
  pointer comparison with NULL                         1  main:1
```

Blockers must go before a proof:

| blocker | what to do |
|---|---|
| `goto`, struct assignment, struct parameters or results, a `switch` that falls off its last case | an idiom patch |
| builtins (`__builtin_expect`, clz/ctz, bswap) | the library's portable switches, or `-D__builtin_expect(e,v)=(e)` |
| unaligned wide memory accesses through cast pointers | the library's "memcpy access" switch |
| `long double`, often through `<math.h>` | configure it out, or leave the unit out |
| calls to libc functions other than those of `libc/` (`memcpy`, `memmove`, `memset`, `memcmp`, `calloc`, `strlen`, `strnlen`, `strcmp`, `strncmp`, `memchr`) | a model of the function in the project, or another target |
| static functions of the same name in two units | nothing: `tools/clight.sh` renames them |

`qp new` links `libc/libc.c`; add `"$GP/libc/string.c=src/string"` to `UNITS` when the code calls the string
functions.

An idiom patch is a command in `PATCH` of `project.conf`, run at the root of the tree and kept with its test in
`projects/mylib/patch/`. Keep each change minimal, with the original in a comment, and test the patched code
against the original on valid, mutated and random inputs. (person) Review the diff and list the patch among the
project's deviations, since the theorem is about the patched code.

## 4. The checks before proving (`qp check`)

`qp check mylib` runs the lint, the spec natively under ASan and UBSan on random inputs (also on the unmodified
code, if patched), the spec under CompCert's interpreter, which runs the semantics of the theorem, and the spec
against mutants of the code. It writes `projects/mylib/CHECK.md`, here in three minutes:

```
== native runs
find_byte_ok         upstream  ok (3000 runs)
== interpreter
find_byte_ok         interp    ok (20 runs, no stop; 13 timed out)
== mutants
mutant  1 mylib.c:8 find_byte  killed by find_byte_ok  -> while (i < n && buf[i] != c)
mutant  2 mylib.c:7 find_byte  killed by find_byte_ok  -> size_t i = 0;
...
Killed by some harness: **4/4**; 0 of the others only hang (the laws do not claim termination).
```

(person) Read `CHECK.md`. "13 timed out" means the slow interpreter ran out of time on inputs of up to 1 KiB, not a
failure. A failing native run is a counterexample: a bug in the code or a mistake in the spec. A stop in the
interpreter is undefined behaviour in CompCert's semantics, a real defect or an idiom to patch (step 3, and
[KNOWN-ISSUES.md](KNOWN-ISSUES.md)). Few killed mutants can mean a weak spec or missed inputs: the spec of
`examples/rle` kills 4 of 14, two of the ten survivors do break it on inputs that random runs seldom build, and its
README explains the rest.

Two more checks help. `tools/fuzz_gate.sh` checks that the `qp_assume`s of a spec let inputs through to its
`qp_assert`s ([HARNESSES.md](HARNESSES.md)), and `qp fuzz mylib --libfuzzer` runs each spec under libFuzzer,
which picks inputs by coverage, on the unmodified code.

## 5. The contract (`qp assemble`)

```sh
qp assemble mylib ../mylib-proof
```

```
5718ace (HEAD -> master, tag: contract) Contract: mylib, 1 theorems (find_byte_ok Admitted), upstream bb0f4f47ec0c, quickproof ...
```

`qp assemble` writes the proof repository ([QP.md](QP.md)): the code under test, the framework as the submodule
`quickproof/`, the Clight of every unit (`src/<unit>/code.v`), one module per unit (`src/units/`), one contract per
spec (`src/contracts/LAW.v`, and `suite.v`, the conjunction of their theorems, when there are several) and
`_CoqProject`. It commits them and tags the commit `contract`. Each contract ends with the unproved theorem:

```coq
Theorem find_byte_ok : harness_safe whole_prog.
Proof.
Admitted.
```

(person) Review the specs, the units each spec links (the comment at the top of each contract file) and the
configuration. These files are now frozen: a proof may only add Coq files under `src/` and replace the `Admitted`
of each theorem.

## 6. The proof

AI agents, or a person who knows VST, write the proof, with [AGENTS.md](AGENTS.md) as the brief. The worked
examples in `quickproof/examples/` show the whole shape of a proof. Here the proof is the files of
`examples/find_byte/proof/`, copied into the proof repository at the same paths
(`cp -r quickproof/examples/find_byte/proof/. .`) and committed.

Three things help. The brief tells the agent that a property may be false, that a counterexample is then the result,
and that it must never weaken the property to get a proof. Give each function one specification that serves every
property ([LINKING.md](LINKING.md)). Settle the loop invariants, or a model of the data format, before the function
bodies.

## 7. The check (`qp verify`)

```sh
qp verify ../mylib-proof
```

`qp verify` runs the acceptance checklist of [QP.md](QP.md) on a fresh clone (shortened):

```
- files changed since the contract: 2; frozen files changed: none
- regenerated code.v: identical to the committed files
- elaborated statement and whole_prog of `find_byte_ok`: identical to the contract
- `Admitted`/`admit`/`Axiom`/`Parameter`/`Conjecture` in the Coq sources of the proof (...): none

| theorem | result | axioms |
|---|---|---|
| `find_byte_ok` | PROVED | 13: standard + VST malloc |

Verdict: PASS (exit 0).
```

(person) Read the report. `VERIFY.md` in the clone adds the full `Print Assumptions` of every theorem, and
[GUARANTEES.md](GUARANTEES.md) says what a PASS means and what it relies on.

## 8. Keeping the proof (`qp export`)

`qp export mylib ../mylib-proof` runs `qp verify` and, on a PASS, stores the proof with `VERIFY.md` and `PROOF.md`
in `projects/mylib/proofs/LABEL/` (default: the date and the commit, here `2026-10-15-eeaa8ca8`).
`qp rebuild mylib LABEL` later rebuilds it from upstream and prints each theorem's status.

## Limits to keep in mind

- The theorem is about CompCert's semantics of C for 64-bit x86 Linux, through `clightgen`. It is stricter than
  native compilers in some places (steps 3 and 4) and more permissive than ISO C in others
  ([GUARANTEES.md](GUARANTEES.md)).
- Partial correctness: a run that never returns is not a counterexample, so bound the loops of a spec.
- [KNOWN-ISSUES.md](KNOWN-ISSUES.md) lists known problems, such as the token renaming of `malloc` and `free`.
