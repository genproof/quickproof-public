# Changelog

All notable changes to QuickProof are documented in this file. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and QuickProof follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-02

The first public release. QuickProof needs Coq 8.20.1, CompCert 3.15 and VST 2.15, and works on 64-bit x86
Linux. `qp import-fuzz` of libFuzzer targets is stable. The other importers and `qp fuzz --libfuzzer` are
previews: they work and are tested on real harnesses, but their interfaces and what they cover may change.

### Added

- `include/quickproof.h`, the environment of a harness: `nondet_u8`, `nondet_u32`, `nondet_size`,
  `nondet_bytes` and `pick` for inputs, `qp_assume` to restrict them, `qp_assert` for properties. The last two
  are macros for `gp_assume` and `gp_assert`, the names the Clight, `Env.v` and the messages of the tools use;
  specs may write either.
- `coq/QuickProof/Env.v` and `Contract.v`: the specifications of the environment functions and
  `harness_safe`, the statement of every theorem. These and `quickproof.h` define what a theorem means; they
  contain no axioms. The whole trusted base, including the translation scripts and `qp verify`, is listed in
  `docs/GUARANTEES.md`.
- `coq/QuickProof/EnvBodies.v`, `Pick.v`, `Link.v` and `Assembly.v`: proofs of the environment functions'
  bodies, and lemmas for linking units and assembling a whole-program proof.
- `libc/`: plain-C `memcpy`, `memmove`, `memset`, `memcmp`, `calloc` and string functions, and the unit that
  owns `malloc` and `free`, proved together with the code that uses them.
- `tools/clight.sh`, `tools/new_contract.py` and `tools/link_units.py`: the C units of a project to Clight with
  `clightgen`, and one theorem per harness and their conjunction `suite`, over the whole program or, with
  `LINK=per-law`, over the units each harness needs.
- `tools/clight_audit.py`: the constructs in the generated Clight that VST cannot handle.
- `qp new` and `qp tree`: a project pinned to an upstream commit and a framework commit, and the code under test
  with its idiom patch.
- `qp lint`, `audit`, `fuzz`, `interp`, `mutants` and `check`: the checks before any proof work. The VST lint,
  native runs under AddressSanitizer and UndefinedBehaviorSanitizer, runs under CompCert's reference
  interpreter, and broken versions of the code that each harness should notice.
- `qp assemble`: the proof repository, with the framework as a submodule and every theorem stated and unproved
  in the commit tagged `contract`.
- `qp verify`: the acceptance check of a proof, from a fresh clone. It refuses a repository without the layout that
  `qp assemble` makes, a framework whose files differ from those of the verifier, a `quickproof.conf` that is more than
  assignments (`tools/conf.py`, which every tool that reads a conf uses), and options or Coq commands that load
  code or switch off a kernel check. It then checks the frozen files, the regenerated Clight, that every
  statement is the `harness_safe` of the program generated from its harness, that nothing is `Admitted`, and
  that only the allowed axioms are used, and it compares the framework with its own again after the translation
  and the builds. Without a contract commit the result is UNVERIFIED, never PASS. `--coqchk` also runs Coq's
  checker. It prints its progress on stderr, stops before the build when a frozen file has changed, and on a
  terminal ends with the table of theorems and the verdict only (`--brief`; `VERIFY.md` has the full
  report). An interrupted run is resumed by the next one on the same commit (`--fresh` starts over). It builds
  the repository's Coq sources, so run it on an untrusted one in a container.
- `qp export` and `qp rebuild`: a verified proof kept in the workspace, and rebuilt from its recorded commits.
- `qp import-fuzz`: a law from a libFuzzer target, unchanged; with `--style afl|honggfuzz`, from AFL++
  persistent-mode and honggfuzz `HF_ITER` harnesses, and with `--entry`, `--init` and `--cleanup`, from other
  entry points. `qp replay` runs an imported law on given inputs, and `qp fidelity` compares imported laws with
  the original targets built the upstream way.
- `qp import-cbmc`: a law from a CBMC proof harness, without CBMC's unwinding bound.
- `qp import-svcomp`: a law from an SV-COMP verification task, and `--verdicts` to compare imported laws with
  the tasks' expected verdicts.
- `qp fuzz --libfuzzer`: every law as a coverage-guided libFuzzer target on the unmodified upstream, with a
  native replay of each crash.
- `qp examples` and `examples/`: three small libraries (a run-length decoder, Adler-32, a byte search), each
  with a law and its proof, checked offline with the framework they ship in.
- `tools/fuzz/determinism.sh`: imported laws regenerate byte for byte in other directories and environments.
- `runtime/fuzz_driver.c`, `runtime/interp_driver.c`, `tools/interp.sh` and `tools/fuzz_gate.sh`: native and
  interpreter runs of a harness, and a check that its assumptions let inputs reach its assertions.
- `docker/`: the Docker image `ghcr.io/genproof/quickproof`, with the toolchain, QuickProof, the examples, the
  MCP server rocq-mcp and the command `qpdemo`: check the examples' proofs, or prove a property of your own
  code by hand or with an AI agent you bring (`docs/DOCKER.md`). `docker/build.sh` builds it from a checkout.
- Documentation in `docs/`: an overview, what a theorem guarantees and relies on, which code fits, writing
  harnesses, a step-by-step recipe, linking several laws, the `qp` command, the three importers, and known
  issues.
- Tests: `tests/run.sh` builds the Coq library, proves a toy suite, runs `tests/qp.sh` (every `qp` command end
  to end on toy projects, offline) and checks the examples.

[Unreleased]: https://github.com/genproof/quickproof-public/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/genproof/quickproof-public/releases/tag/v0.1.0
