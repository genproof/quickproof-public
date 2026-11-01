# Guarantees and trust

This page says what a QuickProof theorem says and what it relies on. Read it before quoting a result.

## Who writes what

| part | written by | checked by | trusted |
|---|---|---|---|
| the specs (the C programs that state the properties), their `qp_assume` bounds, `quickproof.conf` | people, or AI agents with people reviewing | native runs, CompCert's interpreter, mutants (tests, not proof) | yes: people read them |
| models of operating-system or kernel interfaces that a project links | people, or AI agents with people reviewing | tests, as the project's list of deviations (for example a `DEVIATIONS.md`) describes | yes: people read them |
| rewrites of idioms that CompCert leaves undefined or VST cannot handle | AI agents or people | differential tests against the original code | tested, not proved |
| function specifications, loop invariants, lemmas, proofs | AI agents | Coq | no |
| the model of the environment (`quickproof.h`, `Env.v`, `Contract.v`), the translation scripts, `qp verify` | QuickProof | review of QuickProof; `qp verify` checks that the Clight is reproduced | yes |
| Coq, VST, CompCert | their authors | their own proofs and tests | yes |

## What the theorem says

Every theorem has the form

```coq
Theorem my_law : harness_safe whole_prog.
```

`whole_prog` is the spec's `main` linked with the code under test, translated to Clight, the C dialect of
CompCert and VST. Each C file is translated on its own (a unit), and VST's `QPlink_progs` links the units
([docs/LINKING.md](LINKING.md)). `harness_safe` (`coq/QuickProof/Contract.v`) is VST's whole-program
judgement, `semax_prog`, for this program, with the specifications of `coq/QuickProof/Env.v` for the
environment. `nondet_u8`, `nondet_u32`, `nondet_size` and `nondet_bytes` may return any value, and `malloc` may
return `NULL`. `nondet_bytes(buf, n)` needs `buf` writable for `n` bytes, or `NULL` when `n` is 0 (as
`malloc(0)` may return).

VST is proved sound in Coq with respect to CompCert's semantics of Clight. Its adequacy theorem
(`whole_program_sequential_safety_ext` in `veric/SequentialClight.v` of VST 2.15) turns a proved judgement into a
statement about runs: no run reaches undefined behaviour, whatever values the environment returns. The theorem has
hypotheses about the external functions that we have not proved in Coq for QuickProof's environment. For `malloc`
and `free`, QuickProof uses VST's malloc library. `VST.floyd.library` declares its `mem_mgr` and `malloc_token`
with `Parameter` and `Axiom`, with no concrete model, so instantiating the theorem would also mean giving them one.
The step to "no run has undefined behaviour" thus rests on VST's design and proved theorem, but it is not yet a Coq
theorem about this environment.

With this caveat, the theorem gives the following, for every input the spec allows:

- every `qp_assert` in the spec holds, because a failing assertion is undefined behaviour;
- the library and the spec are memory safe: no access outside an object, no use after `free` and no
  double free, no null pointer dereference, no use of an uninitialised value;
- there is no division by zero and no shift by a negative amount or by the width of the type or more;
- there is no signed overflow in `+`, `-` and `*`. CompCert defines it (the result wraps around), and VST's
  checks rule it out;
- pointers are compared only where CompCert defines it: an ordering comparison only within one object (up to
  one past its end), and an equality test across objects only between in-bounds pointers;
- all the code that runs is part of the proof. A call of a function that is not linked in counts as a failure
  (`QuickProof.Link.honest_rejects_foreign`).

`qp_assume(c)` cuts off the runs where `c` is false. Otherwise sizes and byte values are symbolic. A bound such
as `qp_assume(n <= 4096)` is part of the property: everything up to it is covered and nothing beyond it.

The theorem says nothing about questions the spec does not ask. A spec that calls only one function, or only
passes valid arguments, gives a true theorem about that case and nothing more
([docs/HARNESSES.md](HARNESSES.md)).

When the library does not check a condition that a `qp_assume` places on its arguments, the theorem says
nothing about calls that break it, but a second spec can show that the library's own callers meet it.

### Undefined behaviour means CompCert's undefined behaviour

"Undefined behaviour" is what makes a Clight program get stuck in CompCert's semantics for 64-bit x86 (from
`clightgen -normalize`), plus VST's checks: signed overflow, uninitialised values, the pointer comparisons
above. This is stricter than ISO C in some places and more permissive in others.

Some things that ISO C defines are undefined in CompCert, so such code cannot be proved as it is:

- an equality test between a pointer one past the end of one object and a pointer into another object;
- copying a pointer byte by byte, as a byte-wise `memcpy` of a struct with pointers does. A byte read of a
  stored pointer gives an undefined value;
- arithmetic comparisons of pointers converted to integers, such as `(uintptr_t)p + len < (uintptr_t)p`.

Some things that ISO C leaves undefined are defined in CompCert, and the theorem does not rule them out:

- Pointer arithmetic outside an object. Computing such a pointer is defined, and VST accepts it; only
  dereferencing or comparing it is undefined. Code that moves a pointer out of its array and back before use
  can be proved, although an optimising compiler may break it and sanitizers do not flag it. zlib 1.2.8 did
  this in `inftrees.c` (`base -= 257`, then `base[257 + i]`; CVE-2016-9840), and a property of that function
  could likely be proved on 1.2.8. zlib 1.2.9 removed the idiom.
- Unsequenced side effects, such as `i = i++ + i++`. clightgen fixes one evaluation order, and the theorem is
  about that order only. A compiler may pick another, or assume that the expression never runs.
- Breaking the effective type rules ("strict aliasing"). CompCert's memory model has no effective types, so
  reading a `float` through an `unsigned int *` reinterprets its bytes, which is defined.
- `restrict`, which clightgen drops. QuickProof's `memcpy` (`libc/libc.c`) is a forward byte loop, defined on
  overlapping ranges, so a library that calls `memcpy` with overlapping buffers can be proved. The system's
  `memcpy` may copy them differently.
- Left shifts of negative values, or of a signed value into or past its sign bit, such as `-1 << 1` and
  `1 << 31`. CompCert defines them, and VST checks only the shift amount.

### What else the theorem does not rule out

- Running forever: VST proves partial correctness.
- Memory leaks. The postcondition of `main` is free, so code that never frees what it allocates can be proved,
  unless the spec counts allocations itself, for example through allocator hooks.
- Running out of stack. Clight's memory has no stack limit.
- Other resources running out (apart from `malloc` returning `NULL`), side channels and hardware faults, which
  are outside the semantics of C.
- Other threads: the theorems are about runs of one thread.
- Compiled code. A binary built with GCC or Clang is not proved to behave as the source does; the permissive
  cases above are where compilers may disagree.
- Other platforms. Sizes and layout are those of 64-bit x86 Linux. Assembly and other platform-specific code is
  not covered. Where a library also has portable C for such code, the portable C is proved.
- The system's libc. `memcpy`, `memmove`, `memset`, `memcmp` and `calloc` come from QuickProof's `libc/`,
  verified with the library.

## What is checked by machine

Coq checks the function specifications, loop invariants and proofs that the AI agents write, the framework's lemmas
(`coq/QuickProof/EnvBodies.v`, `Link.v`, `Assembly.v`, `Pick.v`), and the proofs of the `libc/` functions
that a program links. `coqc` checks the proofs as it builds them, and
`qp verify --coqchk` also runs `coqchk`, Coq's independent checker, on the modules of the proof and of the
framework; that is not the default yet.

`qp verify` checks the procedure around the proof on a fresh clone ([docs/QP.md](QP.md) has the full list):

- since the commit tagged `contract`, which holds the specs, the code and the unproved theorems, only proof
  sources and notes have changed;
- the Clight, generated again from the C code, is identical to the committed Clight;
- the statement of every theorem, as Coq elaborates it, is identical to the one at the `contract` commit;
- every theorem is proved, and its `Print Assumptions` names only the allowed axioms (`ALLOWED_AXIOMS` in
  `tools/qp`), so an `Admitted` lemma that a theorem depends on fails the check;
- the proof's own Coq sources (`src/` and the other files of `_CoqProject`, comments excluded) contain no
  `Admitted`, `admit`, `Axiom`, `Parameter` or `Conjecture`, not even in a lemma that no theorem uses. In a
  `run/prebuild` project (a vendored library) they are only listed, and `Print Assumptions` decides whether a
  theorem depends on them.

The allowed axioms are standard ones (excluded middle, functional, propositional and set extensionality, proof
irrelevance, `eq_rect_eq`, and two axioms of Coq's classical reals) and VST's malloc library. Every theorem so
far reports 13 or 14: eight standard axioms and VST's `mem_mgr`, `malloc_token`, `create_mem_mgr`,
`malloc_token_valid_pointer`, `malloc_token_local_facts` and, in the zlib and OpenSSL proofs,
`malloc_token_change_composite`.

## What has to be trusted

These parts are not checked by machine, and the result depends on them.

- Coq 8.20.1 and its kernel. VST 2.15 supports only Coq 8.19 and 8.20; from 9.0 on, Coq is called the Rocq
  Prover.
- VST 2.15: its adequacy theorem (above), its malloc library's declarations and axioms, and `QPlink_progs`.
- CompCert 3.15's semantics of C, with the differences from ISO C above.
- `clightgen`, configured for 64-bit x86 Linux. It runs the system's C preprocessor on the system's headers,
  and its parsing, elaboration and printing of the Coq file are not formally verified.
- The translation scripts between `clightgen` and the theorem, since a mistake in them could change the
  program; `qp verify` checks only that the committed Clight is what they produce. `tools/conf.py` checks that
  `quickproof.conf` (units, include paths, defines) is data: assignments only, with the words that
  [docs/QP.md](QP.md) lists. `tools/clight.sh` runs `clightgen` on every unit with `-Dmalloc=quickproof_malloc
  -Dfree=quickproof_free` (a renaming of tokens, see [docs/KNOWN-ISSUES.md](KNOWN-ISSUES.md)), renames statics
  that two units define under the same name, and rewrites `code.v` with `sed` to record the source file name
  and give string literals a per-unit prefix. `tools/tag_anon.py` tags the typedef'd anonymous structs and
  unions of the preprocessed C, and `tools/canon_anon.py` gives the other anonymous composites that several
  units share one name. `tools/new_contract.py` and `tools/link_units.py` write the unit modules, `whole_prog`
  and the theorem statements.
- The argument for `LINK=per-law`, which [docs/LINKING.md](LINKING.md) makes on paper: the program with only
  the units a spec needs has undefined behaviour exactly when the program with every unit has.
- QuickProof's model of the environment (`include/quickproof.h`, `Env.v`, `Contract.v`), which defines
  `nondet_*`, `qp_assert`, `qp_assume` and the shape of every theorem. It contains no axioms.
- `qp verify` (`tools/qp`). A mistake in it could accept a proof of a statement other than the property.
- The contract at the commit tagged `contract`: the specs, their `qp_assume` bounds and `quickproof.conf`,
  which people write or review and only tests check (native runs, CompCert's interpreter, mutants), and the
  `quickproof/` framework the theorems are stated in.
- The project's list of deviations (for example a `DEVIATIONS.md`), which a result should be quoted with. Its
  idiom patches, for code that CompCert leaves undefined or that uses `goto` or struct assignment, are tested
  against the original, not proved equivalent. Its models of operating-system and kernel interfaces (locks,
  clocks, random numbers, reference counting, special allocators) are trusted to describe the real interface, so
  read them like a spec.

`qp verify` runs no script of the repository and refuses a `quickproof.conf` that is more than data and the
known ways of loading code into Coq. It still builds the repository's Coq sources with your rights, so check
untrusted proofs inside a container, such as the Docker image.

## Quoting a result

A fair summary names the code (library, files and upstream commit), states each property in a sentence, and
lists the deviations.
