# Laws from SV-COMP tasks: `tools/qp import-svcomp`

`tools/qp import-svcomp` turns an SV-COMP verification task, compiled as is, into a law, with the task's expected
verdict as an oracle for the import. A task is a C program whose `main` draws inputs from `__VERIFIER_nondet_*()`,
restricts them with `__VERIFIER_assume` and calls `reach_error()` on a violation, with a task-definition file that
names its properties and the expected verdict of each. "Law" means a property written as a QuickProof harness
([QP.md](QP.md)); this page keeps the word because SV-COMP's properties are `unreach-call` and the rest.

QuickProof reads the task format, so that an SV-COMP-style harness you already have becomes a law; it does not
compete in SV-COMP. The importer is a preview in v0.1: it works and is tested on real tasks from sv-benchmarks, but
its interface and what it covers may change. A law that passes the gates is ready for a proof, not proved, and no
property imported from SV-COMP has been proved yet. AI agents write the proofs; Coq and `tools/qp verify` check
them.

```
tools/qp import-svcomp NAME TASK.yml [--property P] [--law L] [--malloc may-fail|never-fails] [--no-check] [--contract]
tools/qp import-svcomp NAME --verdicts [LAW..] [-n RUNS] [--timeout S] [--budget S] [--interp N] [--interp-timeout S] [--out FILE]
```

`TASK.yml` is a path in the project's upstream at its pinned commit, usually sv-benchmarks itself
(`c/coreutils-v9.5-units/relpath_path_common_prefix_valid_functional.yml`), or your own repository of tasks. The
importer takes task-definition format 2.0 and 2.1, with one input file (`.c` or preprocessed `.i`).

## What the import produces

- `harness/LAW.c`, the law: the shim, the task's C file with its `main` renamed `qp_svcomp_task_main`, plain-C
  versions of the C library functions the task calls, and a `main` that calls the task's. Its first comment states
  the claim. The second, the provenance, records the importer version, the command that regenerates it, the
  upstream and commit, the sha256 of the task-definition, input and property files, the task's expected verdicts,
  the law's expected verdict, the edits of the task text and the sha256 of every generated file.
- `harness/svcomp/LAW.i` (or `.c`), the task's C file, unchanged except for these edits, each counted in the
  provenance:
  - a call of `qp_svcomp_reach_error()`, a failing check, at the start of the body of `reach_error`, so that every
    call of it fails, whatever the body does;
  - glibc's expansion of `assert()` in preprocessed files, a GNU statement expression that CompCert does not
    accept, becomes the equivalent conditional call of `__assert_fail`, and `__PRETTY_FUNCTION__` becomes
    `__func__`;
  - an asm label of a declaration (`__asm__ ("" "__isoc99_fscanf")`), which CompCert does not accept, is kept for
    gcc only; it renames an external function, which the theorem does not have anyway;
  - `__attribute__((__cdecl__))`, which tasks preprocessed with Cygwin's headers put where CompCert cannot parse
    it, is removed; it has no effect on x86-64.
- `harness/svcomp/svcomp_env.h` and `harness/svcomp/svcomp_libc.h`, copies of `tools/svcomp/` with a provenance
  line.
- the law's unit in the importer's block of `quickproof.conf`, and, for a law expected to be false, its name in a
  block of `project.conf` that adds it to `BROKEN` (left out of `suite`).

Unless `--no-check` is given, the importer then translates the law's program with clightgen and lists what lies
outside the framework (external functions, undefined globals) and what VST cannot take in the law's cone (the audit
of `tools/qp lint`). `--contract` builds the law's contract once.

The output is a pure function of the task files at the pinned commit, the options, the two files of
`tools/svcomp/` and the importer's version, so importing again changes nothing.

## What the theorem says

The theorem says that no execution of the law that satisfies the task's `__VERIFIER_assume` calls has undefined
behaviour in CompCert C, for every value of every `__VERIFIER_nondet_*` call:

| property file | what a proof of the law implies |
|---|---|
| `unreach-call.prp` | `reach_error()` is never called (every `qp_assert` holds) |
| `valid-memsafety.prp` | no invalid dereference and no invalid free (valid-deref, valid-free); valid-memtrack, that allocated memory stays reachable, is not covered |
| `no-overflow.prp` | no signed overflow in `+ - * /` and unary `-` (VST's type checks; signed shifts are not checked) |
| `valid-memcleanup.prp` | every block from `malloc` or `calloc` is freed when the program ends, by returning from `main` or by `abort()` or `exit()` |
| `termination.prp`, `no-data-race.prp`, `def-behavior.prp`, coverage | not covered |

Whatever property a law is imported for, its theorem implies the first three rows at once: an `unreach-call` law is
also a memory-safety law. So a task that SV-COMP checks for one property only, and that violates another of the
three, gives a false law.

The shim `tools/svcomp/svcomp_env.h`, plain C on top of `quickproof.h` verified with the law, follows the SV-COMP
rules:

| in the task | in the law |
|---|---|
| `__VERIFIER_nondet_T()` for `char`, `uchar`, `short`, `ushort`, `int`, `uint`, `unsigned`, `u32`, `long`, `ulong`, `longlong`, `ulonglong`, `size_t`, `loff_t`, `sector_t` | every value of the type |
| `__VERIFIER_nondet_bool()` | 0 or 1 |
| `__VERIFIER_nondet_memory(p, n)` | `nondet_bytes(p, n)` |
| `__VERIFIER_assume(c)` | `qp_assume(c != 0)` |
| a call of `reach_error()`, `__VERIFIER_error()` | `qp_assert(0)` |
| `abort()`, `exit(s)`, a failing `assert()` elsewhere (`__assert_fail`) | the end of the execution without error (`qp_assume(0)`): in SV-COMP only the property's events are errors |
| `malloc(n)` | the framework's `malloc`, which may return NULL, with arbitrary contents (SV-COMP gives fresh memory arbitrary values; reading it would be undefined in CompCert); `--malloc never-fails` assumes it returns a block |
| `calloc(n, s)` | zeroed; NULL when `n * s` overflows |
| `alloca(n)` | `n` arbitrary bytes that are always there and not a heap block (`free` of it is undefined) |
| `memcpy`, `strlen`, `strcmp`, ... (20 functions) | plain C in `tools/svcomp/svcomp_libc.h` for the theorem and the interpreter; native runs use the system's |

A task that defines one of these functions itself (its own `__VERIFIER_assume`, its own `strlen`) keeps its
definition; the provenance lists them.

The law is stricter than SV-COMP in that reading an uninitialised local and comparing pointers into different
objects for order are undefined. It is weaker in that an `alloca` block lives until the end of the run (in C, until
its function returns) and leaks are covered only with `valid-memcleanup`. Termination is never covered: a run that
loops forever is not a failure.

## Expected verdicts

A law is expected to be false when its task is expected to violate `unreach-call`, `no-overflow`,
`valid-memsafety` with subproperty `valid-deref` or `valid-free` (a `valid-memtrack` violation, a leak, is not one),
or, for a law imported for it, `valid-memcleanup`. Such a law goes to `BROKEN`: a proof attempt must fail, and the
counterexample is the expected result. A law is expected to be true when its property is expected true and no
implied property is expected false; otherwise its verdict is unknown.

`tools/qp import-svcomp NAME --verdicts [LAW..]` runs each law natively under ASan and UBSan
(`runtime/fuzz_driver.c`, up to `-n` runs within `--budget` seconds; `exit` and `abort` end a run without error)
and under CompCert's interpreter (`--interp` seeds). Per law it reports the failing runs and the kind of the first
failure, the runs that reached the end of the task, and the interpreter's verdict, in `projects/NAME/SVCOMP.md`. A
law expected false should show a counterexample, and a law expected true should not; the exit status is 1 when a
law expected true shows one. Random runs prove nothing either way. A law expected false without a counterexample
may only need inputs that random values rarely hit, and tasks that filter their inputs by exiting rarely reach
their end on random values.

The other gates of `tools/qp` (`fuzz`, `interp`, `audit`, `check`) work on imported laws as on any law.

## What is refused

The importer refuses a task, and writes nothing, for data model ILP32 or none given (QuickProof is x86-64 LP64
only), another language than C, more than one input file, no property the theorem implies,
`__VERIFIER_nondet_float`, `_double`, `_pointer`, `_pchar`, `_pthread_t`, `_int128` and `_uint128`, an unknown
`__VERIFIER_` function, threads and `__VERIFIER_atomic_*`, `setjmp`/`longjmp`, inline assembly, `__int128`, a
`main` that takes arguments, calls of input functions (`fgets`, `scanf`, `read`, `rand`, ...: Juliet's data
sources, which have no model yet), and an `unreach-call` property about another function than `reach_error` or
`__VERIFIER_error`.

The check after the import reports what blocks a proof until a patch removes it: `goto` (about half of the LP64
tasks, mostly CIL-generated device-driver code), struct copies, variadic functions, casts between pointers and
integers, C library functions without a plain-C version (`printf`, `realloc`, ...), and GNU statement expressions
other than glibc's `assert` (gnulib's `error()`, for one), which clightgen rejects.

## A project for SV-COMP tasks

1. `tools/qp new NAME https://gitlab.com/sosy-lab/benchmarking/sv-benchmarks.git --ref COMMIT`, or a local clone
   as the upstream. The laws need nothing from the tree, so set `CODE` to something small, such as `c/properties`:
   `tools/qp tree` and the gates copy `CODE`.
2. In `quickproof.conf`, list no library unit: `LINK=per-law`, `INC=()`, `DEFS=()`, `UNITS=()` (the importer adds
   the laws' units). A law carries its own header-free C library, and `malloc` and `free` are functions of the
   environment. `tools/interp.sh` puts every unit in one translation unit with the task, and a unit's system
   headers (even `<stddef.h>` in `libc/malloc_unit.c`) can conflict with the C library declarations of another
   platform that a preprocessed task brings; the importer warns about such units.
3. `tools/qp import-svcomp NAME TASK.yml` per task, with `--property P` when the task lists several and the first is
   not the one wanted, and `--law L` when two tasks have the same file name.
4. `tools/qp import-svcomp NAME --verdicts`, then `tools/qp check NAME`, and the proofs as for any project.
