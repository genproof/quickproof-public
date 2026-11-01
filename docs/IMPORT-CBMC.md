# Laws from CBMC proof harnesses: `tools/qp import-cbmc`

`tools/qp import-cbmc` turns a CBMC proof harness, unchanged, into a law (a property written as a QuickProof
harness, [QP.md](QP.md)). CBMC checks a harness for all values, but only up to the loop unwinding bounds that every
proof sets. The law's theorem covers every input the harness admits and every number of loop iterations. AWS and
FreeRTOS keep about 1,400 such harnesses, for aws-c-common, s2n-tls, coreMQTT, coreHTTP and other libraries.

The importer is a preview in v0.1: it works and is tested on real harnesses (the proofs of coreMQTT, coreHTTP and
aws-c-common), but its interface and what it covers may change. No property imported from CBMC has been proved
yet. Like `tools/qp import-fuzz` ([FUZZ-IMPORT.md](FUZZ-IMPORT.md)), it is deterministic (no LLM), it records where
every line came from, and it is not trusted. A person reviews the law and the shim that models `__CPROVER_*`. That
the shim behaves like CBMC is tested, not proved ("Fidelity").

```
tools/qp import-cbmc NAME PROOF_DIR [--law L] [--entry FN] [--set NAME=VALUE].. [--undef NAME]..
                     [--malloc auto|may-fail|never-fails] [--approx-mem-predicates] [--no-env]
                     [--no-check] [--runs N] [--interp N] [--contract]
tools/fuzz/determinism.sh [--workspace DIR] NAME
```

`PROOF_DIR` is a proof directory of the pinned upstream in the cbmc-starter-kit layout, such as
`test/cbmc/proofs/MQTT_MatchTopic` in coreMQTT. `CODE` in `project.conf` must cover the proof tree and the library
sources. `projects/NAME/cbmc.conf` (bash, optional) may set `IMPORT_OPTS`, options put before those of the command
line (aws-c-common: `IMPORT_OPTS=(--undef CBMC)`).

| option | meaning |
|---|---|
| `--law L` | the law's name (default: the proof's `PROOF_UID`) |
| `--entry FN` | the entry function (default: `HARNESS_ENTRY`, else `harness`) |
| `--set NAME=VALUE` | change a bound: a make variable, a `-D` define, or a macro the harness code defines |
| `--undef NAME` | drop a `-D` define (`--undef CBMC`: build the library as for production) |
| `--malloc` | harness allocations may fail (`may-fail`, CBMC's default) or never fail (`never-fails`, for proofs that pass `--no-malloc-may-fail`); `auto` (the default) follows the proof |
| `--approx-mem-predicates` | accept the pointer-validity predicates, replaced by true (below) |
| `--no-env` | do not write `env/LAW.c` |
| `--no-check`, `--runs N`, `--interp N` | the checks after the import (below): none, native runs (default 1000, 0: none), interpreter runs (default 0) |
| `--contract` | build the law's contract once (`qp assemble`) |

The importer reads the Makefiles as text and never runs make (upstream Makefiles run `$(shell ...)`). It follows
`include`, evaluates `=`, `:=`, `?=` and `+=` in order, and skips `ifeq ... endif` blocks, saying so in the law when
such a block sets a variable it uses.

## What the import produces

- `harness/LAW.c`, the law. Its first comment is the claim, generated from the options (allocation policy, bounds
  kept or widened, `--undef`, approximated predicates, uninterpreted functions);
  `tests/cbmc/expected/mqtt/harness/MQTT_MatchTopic.c` shows one. The second is the provenance: the command that
  regenerates the file, the upstream URL and commit, the sha256 of every Makefile read, of every harness source and
  of the shim, the effective options, the library units and flags, every edit of the harness code, the dropped
  unwinding bounds and the warnings. Then come the proof's own defines, `#include "cbmc/cbmc_env.h"`, the rewritten
  harness code, the generated functions and `main`. `main` calls the entry function and ends with `qp_assert(1)`, a
  trivially true marker that shows the non-vacuity gate that runs get past the assumes.
- `harness/cbmc/LAW/*.c`, the harness code (`PROOF_SOURCES`, and `PROJECT_SOURCES` that live in the proof tree),
  each with its upstream path and sha256 and a `#line` directive, so that compiler messages point at the upstream
  file. The only edits are insertions after declarations, typed allocations and the paths of headers next to the
  original file; the law lists them all.
- `harness/cbmc/cbmc_env.h`, a copy of the shim `tools/cbmc/cbmc_env.h` with a provenance line.
- `env/LAW.c`, a value distribution for native and interpreter runs (`tools/cbmc/cbmc_values.c`), for testing only.
  Most of the time a small object gets a small value, so that assumptions such as `__CPROVER_assume(n < 10)` hold
  in random runs. A hand-written `env/LAW.c` is never overwritten.
- a block of `quickproof.conf`, computed from all the project's imported laws: the include paths and defines that
  configure the library, the library units (`PROJECT_SOURCES` outside the proof tree), `$GP/libc/string.c`
  (plain-C `strlen`, `strnlen`, `strcmp`, `strncmp`, `memchr`), the framework's `libc.c` and malloc unit if
  missing, and one unit per imported law.

A define of the proof that changes the preprocessed text of a library unit configures the library. It goes to the
block, for the whole project, and two laws that need different values of it are refused. Any other define, such as
the bound `-DMAX_TOPIC_NAME_FILTER_LENGTH=10`, is a `#define` at the top of the law, and only the harness code sees
it.

## How it differs from what CBMC checked

| CBMC | the law |
|---|---|
| loops unwound up to `UNWINDSET`/`--unwind`, with unwinding assertions | dropped and listed in the law: every number of iterations; termination is not covered |
| `--bounds-check`, `--pointer-check`, `--div-by-zero-check`, `--undefined-shift-check`, `--pointer-primitive-check` | covered: undefined behaviour in CompCert's semantics |
| `--signed-overflow-check` | covered: VST's type checks require its absence |
| `--unsigned-overflow-check`, `--conversion-check` (on by default in the starter kit) | not covered: defined behaviour in C |
| `--pointer-overflow-check` | weaker: CompCert defines an out-of-bounds pointer until it is used |
| `--float-overflow-check`, `--nan-check` | not covered: arbitrary floating-point values are refused |
| `--memory-leak-check` | not covered |
| uninitialised reads, which CBMC does not flag | undefined behaviour in library code (stricter, like MSan) |
| size bounds in `DEFINES` | kept as they are; `--set` widens them (the recommended second step) |
| `__CPROVER_uninterpreted_f`: the same result for the same arguments | an arbitrary result at each call: the law covers more executions and may fail where the proof relies on consistency |
| a function pointer left uninitialised: any value | NULL (a warning) |
| a call through a declaration without a prototype | undefined in CompCert's semantics: the law fails at such a call (a warning names them) |

So a proved law is stronger than the CBMC proof in three ways (no bound, uninitialised reads in the library,
independent uninterpreted results) and weaker in the checks listed as not covered. A law that fails where the CBMC
proof passes is either a defect beyond CBMC's bound, a defect CBMC does not look for, or one of these known
differences; the importer cannot tell which.

## The translation

The shim `tools/cbmc/cbmc_env.h` maps CBMC's vocabulary onto `quickproof.h`:

| CBMC | law |
|---|---|
| `__CPROVER_assume(c)` | `qp_assume((c) != 0)` |
| `__CPROVER_assert(c, msg)`, `__CPROVER_precondition`, `__CPROVER_postcondition` | `qp_assert((c) != 0)` |
| `assert(c)` (glibc's `__assert_fail`), in harness or library code | `qp_assert(0)` when `c` is false |
| `__CPROVER_cover(c)` | nothing (a coverage goal, not a property) |
| `__CPROVER_havoc_slice(p, n)` | `nondet_bytes(p, n)` |
| `__CPROVER_uninterpreted_f(args)` | a generated function with an arbitrary result |
| body-less `nondet_T(...)`, declared or called without a prototype | a generated function: any value of `T`, arguments ignored |
| `__thread`, `_Thread_local` | removed (a law is single-threaded) |

Uninitialised variables in harness code, and the parameters of the entry function, get an arbitrary value of their
type, inserted after the declaration (`QP_CBMC_HAVOC*` in the rewritten file; the header of `cbmc_env.h` gives the
rule per type). A `_Bool` is 0 or 1. A data pointer is NULL or a fresh block of 0 bytes, not NULL but unusable,
the closest plain-C model of CBMC's invalid pointer. Structs are filled field by field, arrays element by element,
and unions as bytes, with a warning. Static and global variables keep C's zero initialisation, as in CBMC.

Allocation in harness code is the framework's `malloc`, which may return NULL, followed by `nondet_bytes` on the
block. `malloc(sizeof(T))` for a struct `T` (also `sizeof(*p)`) becomes a generated typed allocation, so that
`_Bool` and pointer fields hold values of their types; `calloc` is unchanged. Library code keeps C's semantics, so
a fresh block there is uninitialised.

A harness file that defines only C library functions (aws-c-common's `memcpy_override.c`, coreHTTP's `strncpy.c`)
is CBMC's model of the C library. The law uses the framework's plain-C functions (`libc/libc.c`, `libc/string.c`)
instead, and says so. Functions the framework does not provide (`strncpy`, `qsort`, ...) show up in the cone check.
`REMOVE_FUNCTION_BODY f` for a function the library does not define (aws-c-common's `abort`) changes nothing: the
harness code's own definition is used, as in CBMC.

### Pointer-validity predicates

`__CPROVER_r_ok(p, n)`, `__CPROVER_w_ok` and `__CPROVER_rw_ok` ask whether `p` points to `n` accessible bytes,
which C cannot ask. `--approx-mem-predicates` replaces them by true where they appear positively (through `&&`,
`||` and parentheses) in an assertion or an assumption. In an assertion the law then checks the accesses that
follow instead, which is weaker than CBMC when a stub never touches the memory (coreHTTP's `httpHeaderStrncpy`
stub only asserts and returns). In an assumption the assumption is dropped, so the law covers more executions.
Anywhere else (a condition, an argument, under `!`) and without the option they are refused. The claim counts each
kind.

### Bounds

`UNWINDSET`, `--unwind` and the unwinding assertions are dropped and listed in the law. Bounds in `DEFINES` stay,
so the law says exactly what the harness says minus the unwinding. For `MQTT_MatchTopic`,
`--set MAX_TOPIC_NAME_FILTER_LENGTH=65536` makes the harness's assumptions true for every `uint16_t` length, and
the law covers every topic name and filter. Widening can make a proof much harder, since some assumptions exist
only to make CBMC terminate.

### Configuration for CompCert

Some libraries change under `-DCBMC` into code only CBMC accepts (aws-c-common: `__CPROVER_forall`,
`__CPROVER_overflow_*` and `__CPROVER_r_ok` in its headers). The importer refuses such code and names the header.
`--undef CBMC` builds the library as for production, and the claim then says that the library's CBMC-only checks
are not part of the law. Compiler configuration goes in `quickproof.conf`, as for any project (aws-c-common:
`-DAWS_COMMON_ATOMICS_INL -DAWS_DECLSPEC_NORETURN= -DAWS_ATTRIBUTE_NORETURN=`). The importer's block always adds
`-D__thread= -D_Thread_local= -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 '-D__has_builtin(x)=0'`.

## Measured

One run of this importer, on 2026-10-15, on the CBMC proofs of public code bases at these commits:

| code | commit | CBMC proofs | translated | pass every check before a proof |
|---|---|---|---|---|
| [coreMQTT](https://github.com/FreeRTOS/coreMQTT) | `b7741e3` | 107 | 75 | 58 |
| [aws-c-common](https://github.com/awslabs/aws-c-common) | `2a29f7e` | 173 | 148 | 25 |

Of the 17 CBMC proofs of [coreHTTP](https://github.com/FreeRTOS/coreHTTP) (`281a624`), one translates. The run used
`--approx-mem-predicates`, and `--undef CBMC` for aws-c-common. The checks before a proof are the Clight audit,
native runs under sanitizers that reach the assertions, and CompCert's interpreter. For 4 of the 58 and 5 of the 25,
a library function takes a struct by value and needs an idiom patch before the proof repository can be made. A law
that passes the checks is ready to prove, not proved.

## Refused

The import stops, writes nothing and gives every reason. On the CBMC proofs of coreMQTT, coreHTTP and aws-c-common
(297 in all, 224 of which translate in the run above), the reasons are:

- `REMOVE_FUNCTION_BODY f` where the library defines `f` (with or without a replacement in the harness code) or
  `f` is static: about 40 proofs (a library patch is future work).
- `__CPROVER_file_local_*` in harness code, a call to a static library function: about 25 proofs.
- `__CPROVER_havoc_object(p)`, whose size is not known in C, and pointer-validity predicates without
  `--approx-mem-predicates` or outside an assertion or assumption: 12 proofs (coreMQTT's network stubs).
- Harness code that a C compiler rejects although CBMC accepts it, with the compiler's message: 12 proofs.
  coreMQTT's `event_callback_stub.c` misspells a struct tag, and aws-c-common's ring buffer proofs compare structs
  with `==`.
- An uninitialised local in a function of a harness header, since only harness `.c` files are rewritten: 3 proofs
  (aws-c-common's `aws_byte_cursor_read_common.h`).

The importer also refuses function and loop contracts (`CHECK_FUNCTION_CONTRACTS`, `USE_FUNCTION_CONTRACTS`,
`APPLY_LOOP_CONTRACTS`, `__CPROVER_requires` and the rest; future work); `__CPROVER_forall`, `__CPROVER_exists`,
`__CPROVER_POINTER_OBJECT`, `__CPROVER_POINTER_OFFSET`, `__CPROVER_same_object`, `__CPROVER_OBJECT_SIZE`,
`__CPROVER_DYNAMIC_OBJECT`, `__CPROVER_overflow_*`, threads, and any other `__CPROVER_` name it does not know;
arbitrary floating-point and 128-bit values, `--nondet-static` (`NONDET_STATIC`), `--restrict-function-pointer`, an
entry function the harness code does not define, harness code that defines `main`, and the older `Makefile.json`
layout of FreeRTOS-Plus-TCP and the FreeRTOS kernel.

## The checks after the import

Unless `--no-check` is given, three checks follow the import.

1. The cone. The project's units go through `tools/clight.sh`, as `qp assemble` translates them, and the Clight
   audit of the law's cone (`tools/clight_audit.py`) reports VST blockers and the external functions the cone
   calls. When `clight.sh` fails only because a library unit passes or returns structs by value (coreMQTT's
   `core_mqtt.c`), the units are translated again with clightgen's `-fstruct-passing` so that the cone can still be
   audited, and the report says that the project needs an idiom patch before `qp assemble`. Functions declared but
   defined nowhere and never called by the cone are listed: CBMC tolerates them, and so does the theorem as long as
   they are not called ([LINKING.md](LINKING.md)).
2. The native gate runs the law `--runs` times, built as `qp fuzz` builds it (ASan, UBSan, its `env/LAW.c`). A
   failing check or a sanitizer report is a finding; an assumption that no run satisfies, or no run reaching the
   end, is vacuity. An allocation too large for the sanitizer returns NULL, as the framework's `malloc` may.
   Undefined functions are left unresolved, and calling one fails the run.
3. With `--interp N`, CompCert's interpreter, the semantics of the theorem, runs the first N seeds whose native run
   passes every assumption. Both drivers and the env file derive the same values from a seed, so these runs reach
   the code under test. When the native gate failed, its first failing seed runs under the interpreter as well. A
   stop there is a counterexample to the law.

`qp check`, `qp fuzz` and `qp interp` work on imported laws as on any other. `qp fuzz`, and the native runs of
`qp check` and `qp mutants`, link an imported law as the native gate does: functions that nothing defines are left
unresolved and named in the result, and a run that calls one fails. List the library's other units in
`quickproof.conf` when the law needs them.

## Determinism

The output is a function of the upstream files at the pinned commit (their sha256 are in the law), the effective
options (the `command:` line), the shim and the importer's version. It contains no time, host, user or absolute path
but `UPSTREAM` as `project.conf` writes it. Importing again with the same inputs leaves every file unchanged.
`tools/fuzz/determinism.sh NAME` regenerates every imported law of the project, fuzz and CBMC alike, twice in other
directories and environments, and compares the files byte for byte.

## Fidelity

The law should fail where the CBMC proof fails. Two ways to check it today:

- Seeded faults. Put a fault in the library with the project's `PATCH` (for `MQTT_MatchTopic`, an off-by-one in
  `matchWildcards`' scan) and import with `--interp N`: the native gate must report it, and the interpreter must
  stop on the failing seed. Without CBMC installed, take faults whose CBMC verdict is known from the upstream
  proof's history.
- Widening. A law that fails only after `--set` points at an input beyond CBMC's bound; confirm it with CBMC at the
  larger bound before reporting it upstream.

## Future work

Replaying a CBMC counterexample (`cbmc --trace --xml-ui`) as the law's input, by the havoc sites listed in the law
(`FILE:FUNCTION:VARIABLE`); `replay-cbmc`; `--all` (an import report for a whole proof directory); patches for
`REMOVE_FUNCTION_BODY` of library functions and for `__CPROVER_file_local_*`; `__CPROVER_havoc_object` of a known
size; struct assignments in harness code, rewritten field by field; function and loop contracts; the
`Makefile.json` layout; `--nondet-static`; leak checks; and checks for unsigned overflow and narrowing conversions
(`--checks=cbmc`).

## Adding a project

1. Run `tools/qp new NAME URL --ref COMMIT`, with the proof tree and the library in `CODE`, and the library's units
   and the compiler configuration CompCert needs in `quickproof.conf`. qp's trees contain no git submodules, so put
   the include directory of a submodule the proofs need in `INC` (coreHTTP's llhttp).
2. Run `tools/qp import-cbmc NAME PROOF_DIR` per proof (`--undef CBMC` where the library has CBMC-only code), read
   the refusals and warnings, then widen the bounds with `--set`.
3. Run `tools/qp check NAME`, `tools/fuzz/determinism.sh NAME` and a seeded fault.
4. Prove: `tools/qp assemble`, and `tools/qp verify` on the result.
