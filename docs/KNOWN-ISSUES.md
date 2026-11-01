# Known issues

Practical problems with the framework, and how to work around them. The general limits are in
[docs/SCOPE.md](SCOPE.md) and [docs/GUARANTEES.md](GUARANTEES.md).

## Installing the toolchain

The README's commands install everything on Ubuntu 24.04. `gcc` brings AddressSanitizer and
UndefinedBehaviorSanitizer for the native runs, and `python3` runs `tools/qp`. Coq needs `libgmp-dev` and
`pkg-config`. `coq-hammer-tactics` provides CoqHammer's `sauto` and `hauto` for proofs. `clang` is needed by
`qp import-cbmc`, `qp fidelity`, `qp fuzz --libfuzzer` and the tests, and opam uses it, or `g++`,
to build Flocq.

In a fresh Ubuntu 24.04 container on 8 CPUs of a busy 16-CPU server, the opam commands took 27 minutes, most
of it VST, and the opam directory takes 2.0 GB. The framework's Coq library builds in under a minute
(`cd coq && coq_makefile -f _CoqProject -o Makefile.coq && make -f Makefile.coq`), and `tests/run.sh` takes
about 10 minutes.

We test with GCC 13.3 and clang 18. The sanitizers of older compilers, such as GCC 12 and clang 14 in
Debian 12, crash at random on kernels that set `vm.mmap_rnd_bits` to 32. The workaround is
`sudo sysctl vm.mmap_rnd_bits=28`.

On macOS or ARM Linux, use the Docker image. opam configures CompCert for the machine it runs on, but every
proof's Clight is for x86_64 Linux, so `qp verify` would find the regenerated Clight different.

## Code must be defined in CompCert's C semantics

These common idioms are undefined in CompCert's Clight semantics, although native runs and sanitizers are
clean. [docs/GUARANTEES.md](GUARANTEES.md#undefined-behaviour-means-compcerts-undefined-behaviour) lists more.

- comparisons involving a pointer outside its object, such as `p + len > end` before `len` is checked, or a
  limit pointer `end - 16` that lies before a short buffer;
- arithmetic comparisons of pointers converted to integers, such as `(uintptr_t)p + len < (uintptr_t)p`;
- ordering comparisons of pointers into different objects, such as a `memmove` that tests `d < s`;
- `==` between a one-past-the-end pointer of one object and a pointer into another, such as a decoder's test
  whether the dictionary ends exactly where the output begins. ISO C defines it.

`qp interp` (`tools/interp.sh`) stops on them with "Stuck state" and names the expression. Patch them
minimally, for example with a comparison of sizes (`len > (size_t)(end - p)`), tested against the original
([docs/RECIPE.md](RECIPE.md), step 3). Only a harness can avoid the `==` case, for example by carving both
buffers from one object.

## Open issues

- `-Dmalloc` and `-Dfree` rename every token (`tools/clight.sh`), so a struct field or local called
  `free` or `malloc` becomes `quickproof_free` or `quickproof_malloc` too. The program means the same when
  every unit is built with the same flags, but proof scripts see the new names. Open: a renaming of calls only.
- `HonestEspec` is tied to one compspecs: `malloc_spec'` and `free_spec'` mention one, and `harness_safe` puts
  the whole program's in the external world. A VSU-style proof whose harness unit lacks a composite of the
  whole program must build its harness component on those composites, or use one compspecs throughout. Open:
  byte-size specifications of `quickproof_malloc` and `quickproof_free`, or a recipe with a helper lemma.
- `memcpy` of pointers. The `memcpy` and `memmove` of `libc/libc.c` copy bytes, and a byte load of a stored
  pointer gives `Vundef`, so copying a struct with pointers is undefined. A harness can copy it field by field.
  Open: a word-wise copy of aligned pointer-sized chunks, or specifications that forbid it.
- Interpreter runs put all library units and the harness in one translation unit and skip units under
  `harness/`, so support units go elsewhere, such as `patch/`. `env.c` and the harness share one namespace for
  statics. Renaming typedef names local to a unit's `.c` file breaks token pasting on them; include
  tables that paste such names through a wrapper unit.
- No shipped specifications or proofs of `libc/libc.c` and `libc/string.c`. A project that links them proves
  the functions its harnesses reach, with the specifications they need.
