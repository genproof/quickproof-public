# Examples

Three small C libraries, written for these examples, each with one property and its proof. They are the
quickest way to see a QuickProof proof checked from start to end on your own machine. An AI agent wrote the
proofs. Nothing it wrote is trusted: Coq checks the proofs, and `qp verify` checks that each theorem is the one
generated from the harness.

With the toolchain installed (see "Installing" in the top-level README), from the root of
this repository:

```sh
tools/qp examples rle      # one example
tools/qp examples          # all three
```

Each check takes one to three minutes, most of it spent building QuickProof's Coq library and loading VST. It
needs no network. For each example, `qp examples`:

1. commits the example's code to a scratch git repository, which stands in for an upstream repository;
2. runs `qp assemble`, which generates the theorem from the harness and commits it, unproved, under the tag
   `contract`;
3. commits the files of the example's `proof/` on top;
4. runs `qp verify` on the result: a fresh clone, the Clight generated again, the proof built, the
   statement compared with the contract's, no `Admitted`, and only the allowed axioms.

It prints the report of `qp verify` and ends with `PASS` or `FAIL` for each example. The framework is this
checkout. When the checkout has uncommitted changes, or is not a git checkout, a snapshot of its files is used
instead, so the check is always of the files on disk. Everything is written under `~/.cache/quickproof/examples`
(`QP_CACHE`).

## The properties

### `rle`: a run-length decoder stays in its buffers

`rle_decode(in, n, out, cap)` reads pairs (count, byte) and writes `count` copies of `byte` to `out`. The
property, in `harness/rle_decode_safe.c`, is the one in the top-level README:

> For every input of up to 4 KiB, `rle_decode` never reports more output than the 256-byte buffer it was
> given, and never reads or writes out of bounds.

It is a narrow property. It says nothing about what the decoded bytes are, so a decoder that writes the wrong
bytes, or stops early, still satisfies it. `qp check rle` shows both sides: of 14 broken versions of
`rle_decode`, the native runs catch 4. Most of the other ten still satisfy the property, but two do not: one
writes a byte past a full buffer, one reads from an empty input. Random runs seldom build those inputs; a proof
would not go through. A round trip through an encoder would notice far more.

### `adler32`: checksumming in pieces gives the same result

`adler32(adler, buf, len)` updates an Adler-32 checksum (RFC 1950) with `len` bytes. The property, in
`harness/adler32_split.c`:

> For every buffer of up to 4 KiB and every split point `k <= n`, checksumming the buffer in two pieces,
> `adler32(adler32(1, buf, k), buf + k, n - k)`, gives the same result as checksumming it in one call,
> `adler32(1, buf, n)`.

This property is about the result as well as safety. Its proof defines Adler-32 in Coq and proves that the C
loop computes it.

### `find_byte`: a search returns a matching position

`find_byte(buf, n, c)` returns the index of the first byte equal to `c` in `buf[0..n-1]`, or `n`. The property,
in `harness/find_byte_ok.c`:

> For every buffer of up to 1 KiB and every byte `c`, `find_byte` returns an index `r <= n`, and when
> `r < n`, `buf[r] == c`.

It does not say that `r` is the first match: a stronger harness would also assert that no byte before `r` is
`c`. The library is called `mylib.c` because this example is meant as a starting point: replace the code and
the harness with your own and follow `docs/RECIPE.md`.

## What is in each directory

| path | what |
|---|---|
| `*.c`, `*.h` | the code under test (listed in `CODE` of `project.conf`) |
| `project.conf` | the project's settings (`docs/QP.md`); `qp examples` fills in `UPSTREAM` and `COMMIT` |
| `quickproof.conf` | the C units of the library |
| `harness/` | the harness: the property, as a C program |
| `proof/` | the files the proof adds to the proof repository, at the same paths: `src/contracts/LAW.v`, the generated contract with the proof of its theorem after it, and `src/proof/*.v`, the specifications and proofs of the library's functions |

Each proof is 230 to 340 lines of Coq, including the generated part of the contract.

After `qp examples NAME` has run, the example's workspace is in `~/.cache/quickproof/examples/NAME/ws`, so the
other `qp` commands work on it, for example the checks that come before any proof work:

```sh
tools/qp --workspace ~/.cache/quickproof/examples/rle/ws check rle
```

The code, harnesses and proofs in this directory are part of QuickProof and under its licence, the PolyForm
Noncommercial License 1.0.0.
