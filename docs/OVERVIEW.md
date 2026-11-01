# Overview

QuickProof turns a C program about a library, an executable spec, into a theorem. AI agents write the proof
of that theorem with the Verified Software Toolchain (VST), and the Coq proof assistant checks it.

## An example

A spec for a run-length decoder that must never report more output than its buffer holds:

```c
int main(void) {
    size_t n = nondet_size();
    qp_assume(n <= 4096);
    uint8_t *in = malloc(n);
    if (in == NULL)
        return 0;
    nondet_bytes(in, n);

    uint8_t out[256];
    size_t m = rle_decode(in, n, out, sizeof out);
    qp_assert(m <= sizeof out);

    free(in);
    return 0;
}
```

`nondet_size()` and `nondet_bytes()` do not produce random values. In the theorem they stand for any value at
all, so the input is any byte string of up to 4096 bytes. `qp_assume` restricts the inputs, and `qp_assert`
states the property. The decoder, the spec and the proof are in [examples/rle](../examples/rle), and
`tools/qp examples rle` checks the proof. From the spec, QuickProof generates the statement

```coq
Theorem rle_decode_safe : harness_safe whole_prog.
```

`whole_prog` is the spec linked with the library, translated to Clight, the C dialect of CompCert and VST.
`harness_safe` is VST's whole-program judgement for it. VST's adequacy theorem turns such a judgement into a
statement about runs: no run has undefined behaviour in CompCert's semantics of C. VST proves that theorem in Coq,
but we have not yet instantiated it in Coq for QuickProof's environment. A failing `qp_assert` counts as undefined
behaviour, so the assertion holds on every allowed input. On those inputs, out-of-bounds accesses, use after free
and signed overflow are ruled out too. [docs/GUARANTEES.md](GUARANTEES.md) gives the exact meaning and the
places where CompCert's undefined behaviour differs from ISO C's.

## Executable specs, tests and proofs

A spec reads like a property-based test. The `nondet_*` calls are the test's generators, `qp_assume` works like
`assume` in Hypothesis or `==>` in QuickCheck, and `qp_assert` is the assertion. A test checks the inputs it
tries. A proof covers every input the spec allows.

Before any proof work, `qp fuzz` runs every spec natively under sanitizers on random inputs. To start from tests
you already have, `qp import-fuzz` turns a libFuzzer target into a spec whose theorem says only that no input of
any length makes the target crash ([docs/FUZZ-IMPORT.md](FUZZ-IMPORT.md)), a starting point for a stronger
property. Harnesses for AFL++ and honggfuzz, CBMC proof harnesses ([docs/IMPORT-CBMC.md](IMPORT-CBMC.md)) and
SV-COMP tasks ([docs/SVCOMP.md](SVCOMP.md)) import too. In v0.1 these other importers are previews.

## How a project goes

1. The code is pinned to an upstream commit. Idioms that the proofs' C semantics leaves undefined, such as
   comparing pointers into two different arrays, get a small patch, tested against the original.
2. People write one spec per property, or review the ones AI agents write
   ([docs/HARNESSES.md](HARNESSES.md)).
3. `qp check` runs each spec natively under sanitizers, under CompCert's reference interpreter and against
   broken versions of the library. `tools/fuzz_gate.sh` checks that its assumptions let inputs through.
4. AI agents write specifications for the library's functions, prove the function bodies, and finish the
   theorem ([docs/AGENTS.md](AGENTS.md)). Nothing they write is trusted.
5. `qp verify` rebuilds the proof from scratch, compares its statement with the one committed before the proof
   work began, and checks its axioms against a short fixed list.

A false property cannot be proved. The agents then look for an input that breaks it, which can show a bug in
the library, a gap in its documentation, or a mistake in the spec. [Bugs found](../README.md#bugs-found) in
the README lists the public bugs.

## The repository

Trusted files define what a theorem means or decide whether a proof is accepted. Coq, VST, CompCert's semantics
of C and its `clightgen` are trusted too; [docs/GUARANTEES.md](GUARANTEES.md) lists all that a result relies on.

| path | contents | trusted |
|---|---|---|
| `include/quickproof.h`, `coq/QuickProof/Env.v`, `coq/QuickProof/Contract.v` | the environment of a spec (`nondet_*`, `pick`, `qp_assert`, `qp_assume`), the specifications of that environment, and `harness_safe`, the shape of every theorem | yes |
| `tools/clight.sh`, `tools/conf.py`, `tools/tag_anon.py`, `tools/canon_anon.py`, `tools/new_contract.py`, `tools/link_units.py` | translation to Clight (checks that `quickproof.conf` is data, runs `clightgen`, renames clashing statics and anonymous composites), the programs `whole_prog` and the statements of the theorems | yes |
| `tools/qp` | checks, assembly, verification, export, imports | `qp verify` yes, the other subcommands no |
| `coq/QuickProof/EnvBodies.v`, `Pick.v`, `Link.v`, `Assembly.v` | lemmas for the proof of a theorem | no |
| `libc/` | plain C `memcpy`, `memmove`, `memset`, `memcmp`, `calloc`, string functions, and the unit that owns `malloc`/`free` | no (verified with the code) |
| `tools/fuzz/`, `tools/importers/`, `tools/cbmc/`, `tools/svcomp/` | the importers, and the shims and C library compiled into imported specs | the shims and library are part of the property |
| `tools/clight_audit.py`, `runtime/`, `tools/fuzz_gate.sh`, `tools/interp.sh`, `tests/`, `examples/`, `docker/` | audits, native and interpreter runs, the framework's tests, example libraries with proofs, the Docker images ([docs/DOCKER.md](DOCKER.md)) | no |

## Where to go next

- [docs/GUARANTEES.md](GUARANTEES.md): what a theorem says and what it relies on.
- [docs/SCOPE.md](SCOPE.md): which code fits, and what a project takes.
- [docs/HARNESSES.md](HARNESSES.md): writing specs.
- [docs/RECIPE.md](RECIPE.md): from an upstream repository to a checked proof.
- [docs/QP.md](QP.md): the `qp` command.
- [docs/AGENTS.md](AGENTS.md): the brief for an agent, or a person, who proves a property.
- [docs/LINKING.md](LINKING.md): several properties of one library with shared specifications.
- [docs/FUZZ-IMPORT.md](FUZZ-IMPORT.md), [docs/IMPORT-CBMC.md](IMPORT-CBMC.md), [docs/SVCOMP.md](SVCOMP.md):
  importing fuzz targets, CBMC proof harnesses and SV-COMP tasks.
- [docs/DOCKER.md](DOCKER.md): the Docker image.
- [docs/KNOWN-ISSUES.md](KNOWN-ISSUES.md): problems we have hit and their workarounds.
- [How QuickProof compares](https://genproof.com/quickproof/docs/comparison) with other tools for checking C code.
