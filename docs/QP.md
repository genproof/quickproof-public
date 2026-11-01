# `tools/qp`: from upstream code to an exported proof

`tools/qp` runs the framework on a project: an upstream C library pinned at a commit, its properties written as
specs (`qp` calls each one a law and keeps it in `harness/`), and their proofs. `qp --help` and `qp CMD --help`
list the options.

Requirements: Python 3, with no dependencies beyond the toolchain; Coq 8.20.1, VST 2.15 and CompCert 3.15
(`coqc`, `clightgen`, `ccomp`) in `PATH`, or an opam switch named by `QP_OPAM_SWITCH`; `git`; `gcc` with ASan and
UBSan; `clang` with libFuzzer for `qp import-cbmc`, `qp fidelity`, `qp fuzz --libfuzzer` and the tests.

CompCert, part of the toolchain and of the Docker image, is under the INRIA Non-Commercial License; commercial use
needs a licence from AbsInt ([License](../README.md#license)).

## The workspace

A workspace holds `projects/NAME/`. It is `--workspace DIR` (before the subcommand), else `$QP_WORKSPACE`, else the
nearest ancestor directory with `projects/`. `qp verify` takes a repository and needs no workspace.

```
WORKSPACE/projects/NAME/
  project.conf      the pins (below)
  quickproof.conf   the library units and their flags (below); qp adds one unit per harness/*.c
  harness/          the specs: one C file per spec (its first comment states the claim), shared headers
  env.c             optional: nondet_* value distributions for native and interpreter runs
  env/LAW.c         optional: those of one spec, instead of env.c
  patch/            optional: the idiom patch (PATCH) and its equivalence test
  fuzz.conf         optional: import-fuzz defaults, the original targets' upstream build (fidelity)
  cbmc.conf         optional: defaults of import-cbmc (IMPORT_OPTS)
  notes.md          optional: sections "## Code" and "## Not covered", for templates (assemble)
  STATUS.md         the specs and their status (written by hand; qp new starts it)
  CHECK.md          written by qp check;  FIDELITY.md  written by qp fidelity
  proofs/LABEL/     proofs written by qp export
```

`quickproof.conf` lists the units (`UNITS`, the C files that `tools/clight.sh` translates one by one into Clight),
their include paths (`INC`) and `-D` flags (`DEFS`), and the linking mode (`LINK`, [LINKING.md](LINKING.md)). For
code whose files cannot be put into one translation unit for CompCert's interpreter, `INTERP_UNITS=(...)` lists the
units `tools/interp.sh` uses instead.

`project.conf` is a bash file:

| field | meaning |
|---|---|
| `UPSTREAM` | the upstream git repository: a URL, or a path (absolute, or relative to the project's directory) |
| `COMMIT` | the upstream commit under test (full hash) |
| `FRAMEWORK` | the framework commit or tag the project is checked with; empty: the checkout qp belongs to |
| `LOGICAL` | the Coq logical root of `src/` in the proof repository (e.g. `Lz4`) |
| `CODE` | the upstream files or directories the proof needs; empty: the whole tree |
| `PATCH` | a command run at the tree's root to patch idioms CompCert or VST cannot take; empty: none |
| `BROKEN` | specs whose properties are known to be false (findings): left out of `suite`, not counted by `mutants` |
| `MUTATE` | more files for `qp mutants` besides the library units (e.g. headers with the implementation) |

A proof repository that others clone needs a `FRAMEWORK` pin that the repository at `QP_FRAMEWORK_URL` has.

## The subcommands

In v0.1, `qp import-fuzz` of libFuzzer targets is stable. `qp import-fuzz --style afl|honggfuzz` and
`--entry`/`--init`/`--cleanup`, `qp import-cbmc`, `qp import-svcomp` and `qp fuzz --libfuzzer` are previews, marked
so below. A preview works and is tested on real harnesses, but its interface and what it covers may change.

| command | what it does |
|---|---|
| `qp new NAME URL [--ref REF] [--framework REV]` | scaffolds `projects/NAME` (without a workspace, the current directory becomes one): `project.conf` pinned to REF (default: the latest release tag) and to the HEAD of the framework checkout (no pin when it is not a git checkout), `quickproof.conf` with `LINK=per-law` and the upstream's C files listed as comments, `harness/`, `STATUS.md` |
| `qp tree NAME [--orig] [--out DIR]` | the code under test (upstream `CODE` at `COMMIT`, the project's files, `PATCH` unless `--orig`, `quickproof/`); prints its path (in the cache unless `--out`) |
| `qp lint NAME [H..]` | the VST lint: switches that fall off their last case, composites with bitfields in the Clight, units clightgen cannot translate, blockers in each spec's cone (the functions it can reach); exit 1 on a finding |
| `qp audit NAME [H..] [-v] [--md F]` | the Clight audit of each cone (`tools/clight_audit.py`): blockers (exit 1) and review items per function |
| `qp fuzz NAME [H..] [-n RUNS]` | native runs of each spec on random inputs under ASan/UBSan (`runtime/fuzz_driver.c`), patched and unmodified |
| `qp fuzz NAME [H..] --libfuzzer [--seconds S]` | preview: each spec as a libFuzzer target (below) |
| `qp interp NAME [H..] [-n RUNS]` | runs under CompCert's interpreter (`tools/interp.sh`), the semantics of the theorems |
| `qp mutants NAME [H..] [-k K]` | K live mutants of the code (comparisons, logical operators, off-by-one constants) against every spec: which spec kills which mutant |
| `qp check NAME [H..]` | lint, fuzz, interp and mutants into `projects/NAME/CHECK.md`, the gate before proving |
| `qp assemble NAME OUT [--reuse L] [--templates DIR]` | the proof repository in OUT (below) |
| `qp verify REPO [--rev REV] [--base TAG] [-v]` | the acceptance checklist (below); exit 0 = PASS |
| `qp export NAME REPO [--rev REV] [--label L] [-v]` | `qp verify`, then the proof into `projects/NAME/proofs/L/` (default label: date and commit) |
| `qp rebuild NAME LABEL` | rebuilds an exported proof at its recorded commits, with each theorem's status |
| `qp examples [NAME..] [-v]` | checks `examples/` (default: all), offline (below) |
| `qp import-fuzz NAME TARGET.c [opts]` | a spec from a libFuzzer target; preview: another entry point (`--entry/--init/--cleanup`), an AFL++ persistent-mode or honggfuzz `HF_ITER` harness (`--style afl\|honggfuzz`) ([FUZZ-IMPORT.md](FUZZ-IMPORT.md)) |
| `qp import-svcomp NAME TASK.yml [opts]`, `qp import-svcomp NAME --verdicts [LAW..]` | preview: a spec from an SV-COMP verification task; `--verdicts`: the imported specs against their expected verdicts, written to `SVCOMP.md` ([SVCOMP.md](SVCOMP.md)) |
| `qp import-cbmc NAME PROOF_DIR [opts]` | preview: a spec from a CBMC proof harness of the upstream, in the cbmc-starter-kit layout ([IMPORT-CBMC.md](IMPORT-CBMC.md)) |
| `qp replay NAME LAW INPUT.. [--interp] [--orig] [--sequence]` | an imported spec on input files, natively or under the interpreter |
| `qp fidelity NAME [LAW..] --corpus DIR [--interp N] [--fault FILE\|OLD\|NEW]..` | imported specs against the original targets, built the upstream way, on a corpus (`FIDELITY.md`) |

`tools/fuzz/determinism.sh [--workspace DIR] NAME` regenerates every spec of a project imported by `import-fuzz` or
`import-cbmc` twice, in other directories and environments, and compares them byte for byte with the project's.

## Specs as libFuzzer targets (`qp fuzz --libfuzzer`)

A preview in v0.1. `qp fuzz NAME [LAW..] --libfuzzer` runs each spec under libFuzzer for `--seconds S` (default 60)
on the unmodified upstream (`--patched`: the patched code). Like the native runs, it is untrusted testing. A crash
is a candidate counterexample to the spec's property, to be replayed and understood, never evidence about a proof.

clang builds the spec from the units, flags and env file that `qp fuzz` uses, with ASan, UBSan and coverage, into a
shared object `law.so`, linked to the driver [`tools/fuzz/law_libfuzzer.c`](../tools/fuzz/law_libfuzzer.c). The
driver feeds the spec's `nondet_*` from libFuzzer's input: byte buffers from its front, scalars from its back. Once
the input runs out, the next 16 draws return zeros and later ones come from a deterministic pseudo-random stream
seeded by the input. With `--nondet env` (the default) the project's env file shapes the input as it shapes the
native runs' random numbers. `--nondet direct` keeps the env file's other functions but draws the values straight
from the input (small values, values near the top and arbitrary ones, chosen by a tag byte).

A failing `qp_assert` is a crash, a failing `qp_assume` rejects the input, and `exit()` ends a run normally, as
under the native driver.

The native driver runs every seed in a fresh process; libFuzzer runs many inputs in one. Before every input the
driver copies back the spec's global data (the writable sections of `law.so`) and frees the blocks the spec left
allocated. The C library's own state (stdio, `rand`, `strtok`, locale), thread-local storage (`errno`) and file
descriptors are not reset. A `malloc` of more than 1 GiB returns NULL, as the theorem's malloc may, instead of an
ASan report. The driver's file header has the details.

Each spec gets a directory in `--out DIR` (default: in the cache) with `fuzz` (the libFuzzer binary, also usable
by hand with any libFuzzer option), `law.so`, `replay` (the same spec and driver built natively with gcc, one fresh
process per input file), `corpus/`, `crashes/` and `fuzz.log`. qp runs `fuzz` and `replay` through the links
`bin/LAW` and `native/LAW`, under the spec's name, which an env file may read; do the same by hand.

For each spec qp prints the executions, the coverage and, for a crash, the failed check or sanitizer report and
the native replay's verdict. `--replay INPUT..` replays inputs on one spec with both builds, and `--build-only`
skips the libFuzzer run. `--lf-arg=ARG` passes more options to libFuzzer (e.g.
`--lf-arg=-dict=FILE`), and `--lf-cflag=FLAG` more flags to clang for the spec's objects (e.g.
`--lf-cflag=-fno-sanitize=pointer-overflow` when a known `NULL + 0` in the code under test stops every run). It
exits 1 if a spec crashed or did not build.

## The proof repository (`qp assemble`)

`qp assemble NAME OUT` writes a git repository with the code under test as `qp tree` makes it, the framework as the
submodule `quickproof/` at the project's framework commit (cloned from a local repository that has it;
`.gitmodules` records `QP_FRAMEWORK_URL`), the Clight of every unit, the contracts, `_CoqProject` and a
`.gitignore` of build products. `tools/new_contract.py` writes one contract per spec, each `Admitted`, and `suite`,
their conjunction without the `BROKEN` specs. qp commits all of it under the tag `contract`. A proof then adds Coq
files under `src/`, and everything else is frozen.

`--reuse LABEL` copies the proof files of `proofs/LABEL` (or of a directory) whose contracts are unchanged.
`--templates DIR` (or `QP_TEMPLATES`) copies every file of DIR to the same path in the repository, with these
`{KEY}`s filled: `PROJECT`, `LOGICAL`, `FRAMEWORK`, `REPO`, `THEOREMS` (the specs and their claims), `CODE`
and `NOT_COVERED` (from `notes.md`), `UNITS`, `CODE_FILES`, `UNIT_FILES`, `UNITS_GLOB`, `FROZEN_CONTRACTS` (the
contract files' declarations, as JSON lines), `VST`, `COMPCERT`, `OPAM_BIN`, and `KEY` for every environment
variable `QP_TEMPLATE_KEY`. Nothing is copied by default.

## `qp verify`: the acceptance checklist

`qp verify` builds the framework, the contracts, the proof and any `run/prebuild` project. It runs no script of the
repository: it reads `quickproof.conf` only after checking that it is data (below), and it refuses Coq's
code-loading features. Still, check a proof repository you do not trust in a container, such as the
[Docker image](DOCKER.md).

Before any build, it refuses a repository unless:

- it has what `qp assemble` makes: `quickproof/`, `quickproof.conf`, a spec in `harness/`, and an `_CoqProject`
  that maps `QuickProof` to `quickproof/coq/QuickProof`, so that `harness_safe` is the framework's;
- `quickproof/` matches this `qp`'s framework in every file that decides what a theorem says or how C becomes
  Clight: `include/quickproof.h`, `coq/QuickProof/`, the plain-C `libc/*.c` linked into every program, and
  `tools/clight.sh`, `conf.py`, `tag_anon.py`, `canon_anon.py`, `new_contract.py`, `link_units.py`. So a copy with
  a weaker `Env.v` is refused. These files are compared, not replaced, so a mismatch is reported. Use the `qp` of
  the framework release the repository pins;
- nothing loads code into Coq or turns off a check of its kernel. The main `_CoqProject` uses only `-Q`, `-R` and
  `-arg` with a warning control. A `run/prebuild` project passes coqc no `-I`, `-impredicative-set`,
  `-type-in-type`, `-noinit` or plugin file. The proof's sources use no `Declare ML Module`,
  `Unset Universe Checking`, `Unset Guard Checking`, `Unset Positivity Checking` or `Extract Constant`. The
  framework's files are not scanned, since they are compared;
- `quickproof.conf` is data. Before bash reads it, `tools/conf.py` checks that it holds only assignments (arrays
  and `+=` included) to upper-case names that neither bash nor the tools use (not `PATH`, `IFS`, `GP`, ...), with
  words that are plain text, quoted text, `$NAME` or the one command substitution
  `$(gcc -print-file-name=include)`. No command, no other substitution, no `if`. Since a conf is part of the
  property a spec states, `-include`, `-imacros`, and `-D` or `-U` of QuickProof's own names (`qp_assert`,
  `qp_assume`, `nondet_*`, `pick`, the allocator, `quickproof_*`) are refused too. Every tool that reads a conf
  makes the same check.

After the translation, after each build and before the verdict, `qp verify` compares the trusted files again; a
change to a tracked file of `quickproof/` is a FAIL.

Then, on a clone (local repositories are cloned without hard links, which git refuses on overlayfs, as in a
Docker container):

1. committed build products are removed;
2. a contract commit resolves (`--base COMMIT`, default the tag `contract`). Without one the statements cannot be
   compared with those the specs generate, so the result is `UNVERIFIED`, never PASS;
3. only proof sources (`src/**.v`), notes (`*.md`, `docs/`) and proving metadata (the full list is `FROZEN_OK` in
   `tools/qp`) changed since the contract. Any other change (specs, code,
   configuration, `_CoqProject`, the framework, generated Clight and unit files) fails;
4. the projects in `run/prebuild` (Coq libraries the main build maps but does not compile) build from source and
   change no tracked file;
5. the regenerated Clight equals the committed files;
6. the contracts and the proof build. Each statement is printed as Coq elaborates it (`Set Printing All`), with the
   sha256 of each `whole_prog`. A typed ascription checks that it is the trusted framework's
   `QuickProof.Contract.harness_safe`, so a repository-defined `harness_safe` is rejected even when it prints as
   `Contract.harness_safe`. `Print Assumptions` names only standard axioms and VST's abstract malloc library (fully
   qualified, by `Locate`);
7. the statements equal those at the contract commit, where the trusted `new_contract.py` generates each spec's
   contract file again from the spec, so a committed `whole_prog` that is not the one the spec generates shows
   up as a changed statement. A file that only restates the theorems (a `laws.v`) and the program-only contract
   files it names are kept as committed. A spec's theorem may be proved where it is stated (its contract file, or
   a `laws.v` on its `whole_prog`) or as a conjunct of a proved `suite`;
8. the proof's own sources (`src/` and the other files of `_CoqProject`, comments excluded) contain no `Admitted`,
   `admit`, `Axiom`, `Parameter` or `Conjecture`, not even in a lemma that no theorem uses. In a `run/prebuild`
   project, a vendored library, they are only listed; `Print Assumptions` shows whether a theorem depends on them.

PASS needs every check and every claimed theorem proved.

The report is printed and written to `VERIFY.md` in the clone, which lists every theorem's axioms. The printed
table counts them and says whether they include VST's malloc library (`13: standard + VST malloc`); `-v` prints
them all. On a terminal, `qp verify` prints only the table and the verdict after the progress lines, which name
every check and every failure. That is `--brief`, the default when stdout and stderr are terminals; `--no-brief`
prints the whole report.

The report names the framework commit the repository pins and whether it is a release tag of the verifier's
repository. When the verifier is the repository's own `quickproof/`, which would compare that copy with itself,
the report says so; check a proof you did not make with a QuickProof checkout of your own. The report also records
the number of build jobs (`--jobs N`, else `QP_JOBS`, else half the CPUs), the CPUs and the load when the run
started, and how long each phase took.

The next `qp verify` of the same commit resumes an interrupted run (a reboot, a killed process) in its cached
clone when the contract, the `qp`, the trusted files, `coqc` and `ccomp` are the same. Every check before the build
runs again, and `make` keeps what was built. The report then says "resumed". `--fresh` starts from a new clone
anyway, and a run that finished is never resumed. One `qp verify` at a time may use a clone.

`--coqchk` also runs coqchk on every module of the proof and of the framework's Coq library; VST, CompCert and
Coq's standard library are taken as compiled.

`qp export` stores the report with the proof, and `PROOF.md` records the upstream, framework and workspace commits
(if the workspace is a git repository), the hashes of the code and contract inputs, and what "proved" means.

## The examples (`qp examples`)

Each example `examples/NAME/` ([examples/README.md](../examples/README.md)) is a project with its specs in `harness/`
and its proof files in `proof/`. `qp examples NAME` commits the `CODE` files to a scratch git repository and pins
the project to it, runs `qp assemble` (the contract, tag `contract`), commits `proof/` on top and runs `qp verify`
on the result. The commits carry a fixed date, so the same files give the same commits. The framework is the
checkout qp belongs to: its HEAD, or a snapshot of its files when it has uncommitted changes or is not a git
checkout. Everything is written under `$QP_CACHE/examples/NAME`, the workspace in `ws/` and the proof repository in
`NAME/`. The exit status is 0 iff every example passes.

## Settings

Machine settings are environment variables, or `KEY=VALUE` lines in `$QP_SITE_CONF`, else `tools/site.conf` (not
tracked; `tools/site.conf.example`). The environment wins.

| setting | default | meaning |
|---|---|---|
| `QP_WORKSPACE` | found from the current directory | the directory that holds `projects/` |
| `QP_CACHE` | `$XDG_CACHE_HOME/quickproof`, else `~/.cache/quickproof` | upstream clones, framework commits, trees, verification clones |
| `QP_OPAM_SWITCH` | none: the toolchain in `PATH` | an opam switch with the toolchain |
| `QP_FRAMEWORK_URL` | `https://github.com/genproof/quickproof-public.git` | the submodule URL of proof repositories; fetched for a pin no local repository has |
| `QP_FRAMEWORK_DIR` | none | a local framework checkout used instead of the pinned commit |
| `QP_TEMPLATES` | none | a template directory for `qp assemble` |
| `QP_JOBS` | half the CPUs for a Coq build, a quarter for runs | jobs of Coq builds (`make -j`) and of the native runs of `qp mutants` and `qp fidelity` |

Native runs set `DEBUGINFOD_URLS` empty, so that sanitizer reports use local debug information only. Network
lookups would make every failing run wait.

## Tests

`tests/qp.sh`, run by `tests/run.sh`, tests the Clight audit, the VST lint, the templates, and every subcommand end
to end on a toy workspace built from `tests/perlaw`, offline (a local upstream and a git snapshot of the framework).
`tests/qp/libfuzzer.sh`, also run by it, checks `qp fuzz --libfuzzer` and needs no Coq toolchain. `tests/run.sh`
ends with `qp examples`.
