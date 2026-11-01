<h1 align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/logo-dark.svg">
    <img alt="QuickProof" src="docs/assets/logo-light.svg" width="440">
  </picture>
</h1>

<p align="center"><b>Tests as Theorems</b><br>Write properties. Prove them for all inputs.</p>

<p align="center">
  <a href="https://github.com/genproof/quickproof-public/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/genproof/quickproof-public/actions/workflows/ci.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="License: PolyForm Noncommercial 1.0.0" src="https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-blue.svg"></a>
  <a href="https://genproof.com/quickproof/docs"><img alt="Docs" src="https://img.shields.io/badge/docs-genproof.com-informational.svg"></a>
</p>

<p align="center">
  <img alt="qp verify rebuilds the proof of the example rle from scratch in Docker and accepts it" src="docs/assets/verify.gif" width="760">
</p>

QuickProof proves properties of C code. You write each property as an executable spec, a small C program you
can run. AI agents write a proof that it holds for every input the spec allows. Coq checks the proof, and anyone
can check it again with `qp verify`.

- We proved C specs of [zlib 1.3.2, WireGuard in Linux, OpenSSL's punycode decoder and zstd's
  decoder](#results). False ones showed [bugs in zlib and in the kernel](#bugs-found).
- To start from tests you already have, `qp import-fuzz` turns a libFuzzer target into a spec: no input of any
  length makes it crash ([docs/FUZZ-IMPORT.md](docs/FUZZ-IMPORT.md)). In v0.1 that import is stable. Its
  options for AFL++ and honggfuzz harnesses and for other entry points, and the importers for CBMC
  ([docs/IMPORT-CBMC.md](docs/IMPORT-CBMC.md)) and SV-COMP ([docs/SVCOMP.md](docs/SVCOMP.md)), are previews. No
  property imported from CBMC or SV-COMP has been proved yet.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/flow-vertical-dark.svg">
    <img alt="How QuickProof works: a spec in C, written by hand or turned into one from an existing libFuzzer, AFL++, honggfuzz, CBMC or SV-COMP harness, and the library's source, built with the flags the project states for 64-bit x86 Linux, are tested first: native runs and CompCert's interpreter look for inputs that break the spec, and mutants check that it is strong enough. They then become one Coq theorem, fixed before any proof, that no run has undefined behaviour, by VST's adequacy theorem, whose instance for QuickProof's environment is upcoming. Your AI agents write the proof, Coq checks it, and qp verify checks it again from a fresh clone. The result is a theorem for every input the spec allows, or a counterexample: an input that breaks the property." src="docs/assets/flow-vertical-light.svg" width="640">
  </picture>
</p>

## Quick start

In Docker:

```sh
docker run --rm ghcr.io/genproof/quickproof verify rle
```

It takes a minute or two on x86-64. `bug` in place of `verify rle` shows a failing property.

### Proving your own code

Two step-by-step guides:

- With the Docker image: [Prove a property of your own code](docs/DOCKER.md#prove-a-property-of-your-own-code).
  `new` starts a project with your function and a spec, `check` tests the spec, and `prove` has an AI agent write
  the proof.
- Without Docker: [docs/RECIPE.md](docs/RECIPE.md) takes a library from its upstream repository to a checked
  proof with `tools/qp`.

[docs/AGENTS.md](docs/AGENTS.md) is the brief for your agent; ours are not included.

### Installing

On macOS or ARM, use the Docker image. On ARM, Docker runs this x86-64 image under emulation, several times
slower. On 64-bit x86 Linux (we test on Ubuntu 24.04):

```sh
sudo apt-get update && sudo apt-get install opam gcc make git python3 libgmp-dev pkg-config clang
opam init --bare                        # once per machine; inside a container add --disable-sandboxing
opam switch create quickproof 4.14.2    # CompCert 3.15 needs OCaml 4
eval $(opam env --switch=quickproof)
opam repo add rocq-released https://rocq-prover.org/opam/released
opam install coq.8.20.1 coq-compcert.3.15 coq-vst.2.15 coq-hammer-tactics.1.3.2+8.20
```

This takes about half an hour, most of it building VST
([what each package is for](docs/KNOWN-ISSUES.md#installing-the-toolchain)). Then run an example and the tests:

```sh
git clone https://github.com/genproof/quickproof-public.git quickproof && cd quickproof
tools/qp examples rle
tests/run.sh
```

## Example

From [examples/rle](examples/rle):

```c
/* Law rle_decode_safe: for every input of up to 4 KiB, rle_decode never reports more output than the buffer it
   was given, and never reads or writes out of bounds. */
#include <stdlib.h>
#include "quickproof.h"
#include "rle.h"

int main(void) {
    size_t n = nondet_size();          /* any length ...    */
    qp_assume(n <= 4096);              /* ... up to 4 KiB   */
    uint8_t *in = malloc(n);
    if (in == NULL)
        return 0;
    nondet_bytes(in, n);               /* any bytes         */

    uint8_t out[256];
    size_t m = rle_decode(in, n, out, sizeof out);
    qp_assert(m <= sizeof out);

    free(in);
    return 0;
}
```

`nondet_*` is the input, `qp_assume` restricts it, and `qp_assert` checks the result. A spec is what `qp` and its
reports call a law. QuickProof turns the spec, linked with the library, into
`Theorem rle_decode_safe : harness_safe whole_prog.` Once proved, the claim in the first comment holds for every
input of up to 4 KiB. This property is narrow: it bounds the length of the output but does not say what the
output should be.

## How it works

1. Pin the code at an upstream commit, and patch idioms that CompCert leaves undefined or VST cannot handle,
   such as `goto`.
2. Write and review the specs.
3. `qp check` runs each spec natively under sanitizers, under CompCert's interpreter and against broken versions
   of the library. False properties usually fail here in seconds.
4. `qp assemble` generates the theorems and commits them, unproved, under the tag `contract`.
5. AI agents write the proof. For a false property they look for an input that breaks it
   ([bugs found](#bugs-found)).
6. `qp verify` rebuilds the proof from a fresh clone, compares the theorems with the contract and checks the
   axioms ([docs/QP.md](docs/QP.md)).

## What you review

Nothing AI agents write for the proof is trusted. You review the spec, which states the property, with its
`qp_assume` lines, its `quickproof.conf`, any models of operating-system or kernel interfaces, and the
[limits](#limitations) of the proof. For zlib 1.3.2 the specs are about 5,500 lines against about 590,000 lines
of proof.

## Results

| code | C specs | proof | check |
|---|---|---|---|
| [zlib 1.3.2](https://github.com/genproof/zlib-full-auto-proofs-public), the core library | 62 | about 590,000 lines of Coq | about 8 hours |
| [WireGuard in Linux](https://github.com/genproof/wireguard-auto-proofs-public) | 38 | about 300,000 lines | about 19 hours |
| [OpenSSL's punycode decoder](https://github.com/genproof/openssl-punycode-auto-proofs-public) | 19 | about 36,000 lines | 17 minutes |
| [zstd's decoder](https://github.com/genproof/zstd-auto-proofs-public) | 44 | about 430,000 lines | about 7 hours |

Each repository's README says what its specs state, what the proof leaves out, and how to check it with your own
QuickProof checkout. Each theorem is about the code its repository holds: an upstream commit with the edits and
fixes listed there. Check times are those of `qp verify` on 16 CPUs.

### Bugs found

We report every bug to its maintainers before we publish anything about it, so this list lags behind the work.

- Linux lib/crypto: Poly1305 and ChaCha20-Poly1305 went wrong for lengths of 4 GiB and more; no caller in the
  kernel passes such lengths. Eric Biggers' [series](https://lore.kernel.org/all/20261014152604.323310-1-ebiggers@kernel.org/)
  fixes it and credits [our report](https://lore.kernel.org/r/20261012-libcrypto-4gib-lengths-v1-0-ea566c129a2e@genproof.com).
- zlib: [#1300](https://github.com/madler/zlib/issues/1300), fixed by [#1326](https://github.com/madler/zlib/pull/1326);
  [#1348](https://github.com/madler/zlib/issues/1348), fixed in `2bed3d61`;
  [#1297](https://github.com/madler/zlib/pull/1297), merged as `066e0b68`; [#1283](https://github.com/madler/zlib/issues/1283),
  closed without a change; four reported by e-mail, fixed upstream in `e7bb9788`, `8179479c` and `c0424159`, or
  documented in `dfa96642`.
- XZ Utils: [#237](https://github.com/tukaani-project/xz/issues/237), closed: the maintainer considers `NULL + 0`
  fine, since C2y defines it.

## Limitations

QuickProof 0.1 is a research preview. The tool, its file formats and its documentation will change.

- The theorem is about the C source as CompCert defines C, on 64-bit x86. The compiler and the system's libc
  are not covered. Undefined behaviour is what CompCert's semantics leaves undefined, plus VST's checks. That
  is stricter than ISO C in some places and more permissive in others
  ([docs/GUARANTEES.md](docs/GUARANTEES.md#undefined-behaviour-means-compcerts-undefined-behaviour)).
- It answers only the question the spec asks.
- It is partial correctness: a run that never returns is not a failure. Memory leaks and running out of stack
  are not ruled out either.
- It covers runs of one thread. Assembly, SIMD intrinsics and most floating-point code are out of reach.
- Idiom patches and models of operating-system or kernel interfaces are tested, not proved. Each proof repository
  lists them: WireGuard in `DEVIATIONS.md`, zlib and OpenSSL in `patch/PATCH.md`, zstd in
  `patch/GENPROOF-PATCH.md`.
- VST's adequacy theorem, from the theorem to "no run has undefined behaviour", is not yet instantiated in Coq
  for QuickProof's environment; that instance is upcoming. Every theorem so far rests on 13 or 14 axioms, standard logical ones and the
  declarations of VST's abstract `malloc` library.
- Coq, VST, CompCert's semantics of C, `clightgen`, QuickProof's translation scripts, its model of the
  environment (`include/quickproof.h`, `coq/QuickProof/Env.v`, `coq/QuickProof/Contract.v`) and `qp verify`
  are trusted.

## Documentation

[Overview](docs/OVERVIEW.md), [examples](examples/README.md), [guarantees](docs/GUARANTEES.md),
[scope](docs/SCOPE.md), [specs](docs/HARNESSES.md), [recipe](docs/RECIPE.md), [`qp`](docs/QP.md),
[agents](docs/AGENTS.md), [linking](docs/LINKING.md), imports ([fuzz targets](docs/FUZZ-IMPORT.md),
[CBMC](docs/IMPORT-CBMC.md), [SV-COMP](docs/SVCOMP.md)), [Docker](docs/DOCKER.md),
[known issues](docs/KNOWN-ISSUES.md), [changelog](CHANGELOG.md),
[comparison](https://genproof.com/quickproof/docs/comparison), [contributing](CONTRIBUTING.md),
[security and disclosure](SECURITY.md).

## Authors

QuickProof was created by [Vladimir Kukharenko](https://github.com/vovunku) and
[Carlos Mangusten](https://github.com/carlosmangusten).

## License

QuickProof is under the PolyForm Noncommercial License 1.0.0 ([LICENSE](LICENSE)), copyright 2026 GenProof. It is
built on the [Verified Software Toolchain](https://vst.cs.princeton.edu/) (Andrew Appel and colleagues at Princeton),
[CompCert](https://compcert.org/) (Xavier Leroy and colleagues at Inria) and [Coq](https://rocq-prover.org/).

The toolchain it uses, which the Docker image ships, includes CompCert under the INRIA Non-Commercial License.
That licence allows educational, research and evaluation use; commercial use of CompCert needs a licence from
AbsInt. Coq is under the LGPL 2.1, and VST under a BSD licence.

We chose a noncommercial license to make QuickProof freely available for community use while reflecting CompCert’s
licensing restrictions. We remind users that commercial use of CompCert requires separate permission.

Required Notice: Copyright 2026 GenProof (https://genproof.com)
