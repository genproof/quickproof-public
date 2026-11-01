# Laws from libFuzzer fuzz targets: `tools/qp import-fuzz`

`tools/qp import-fuzz` turns a fuzz target, compiled as is, into a law (a property written as a harness,
[QP.md](QP.md)) whose theorem says that no input of any length makes the target crash, in the sense of libFuzzer.

The importer is a deterministic program (no LLM, no randomness, no time or host in its output). It is not trusted:
a person reviews the law it writes, shim included. That the shim behaves like libFuzzer is tested, not proved, by
`qp fidelity` (below).

The `LLVMFuzzerTestOneInput` targets that AFL++, honggfuzz, Centipede and OSS-Fuzz run import as libFuzzer targets,
stable in v0.1. Other entry points (`--entry`, `--init`, `--cleanup`) and AFL++ or honggfuzz harnesses (`--style`)
are a preview: they work and are tested on real harnesses, but their interface and what they cover may change.

```
tools/qp import-fuzz NAME TARGET.c [--law L] [--style libfuzzer|afl|honggfuzz] [--entry FN]
                     [--max-len N] [--stateful K|unbounded]
                     [--alloc limit|assume|may-fail] [--malloc-limit-mb M] [--leaks|--no-leaks]
                     [--init [FN]|--no-init] [--cleanup FN] [--const-input full|loose|off]
                     [--support FILE].. [--alloc-hook NAME=malloc|calloc|free].. [--define NAME[=VALUE]]..
                     [--no-check] [--contract]
tools/qp replay NAME LAW INPUT.. [--interp] [--orig] [--sequence]
tools/qp fidelity NAME [LAW..] --corpus DIR [--interp N] [--fault FILE|OLD|NEW]..
tools/fuzz/determinism.sh [--workspace DIR] NAME
```

## What the import produces

For a target `TARGET.c`, a path in the pinned upstream tree such as `ossfuzz/round_trip_fuzzer.c`, the importer
writes:

- `harness/LAW.c`, the law. It contains no code of the target. It `#include`s the shim, then the target and its
  support files (`--support`, e.g. lz4's `ossfuzz/fuzz_data_producer.c`) from the tree, so they are compiled as
  is, in one translation unit. Then come the allocation hooks (`--alloc-hook`) and the driver `main`:

  ```c
  size_t n = nondet_size();
  qp_assume(n <= MAX_LEN);                      /* --max-len only */
  uint8_t *data = qp_fuzz_raw_malloc(n);         /* a fresh buffer of exactly n bytes, as libFuzzer's copy */
  qp_assume(data != NULL);
  nondet_bytes(data, n);
  /* copy = a copy of data (--const-input) */
  (void) LLVMFuzzerTestOneInput(data, n);         /* the return value is ignored, as by libFuzzer */
  qp_assert(memcmp(copy, data, n) == 0);         /* --const-input full */
  ...
  qp_assert(qp_fuzz_live == 0);                   /* --leaks */
  ```

  Its first comment states the claim. The second, the provenance, gives the importer version, the command that
  regenerates the file, the upstream URL and commit, the target path, the sha256 of the target, of each support
  file and of the shim, and the effective options.
- `harness/fuzz/libfuzzer_env.h`, a copy of the shim `tools/fuzz/libfuzzer_env.h` with a provenance line.
- the law's unit, in the importer's block of `quickproof.conf`.

`qp assemble` generates the contract, as for every law; `--contract` builds it once right away.

Unless `--no-check` is given, the importer then translates the law's whole program with clightgen
(`tools/clight.sh`) and reports the VST blockers of the law's cone, as `tools/qp lint`, `check` and `audit` do: a
switch on a non-int, goto, struct copies, parameters and results, builtins, byte copies of pointer-holding memory,
conversions between pointers and integers. It also lists what lies outside the framework: external functions other
than `nondet_*`, `gp_assert`, `gp_assume`, `quickproof_malloc`/`quickproof_free` (e.g. `realloc`, `snprintf`),
global variables without a definition (e.g. `stderr`), and clightgen's errors (struct returns: an idiom to patch).
A law with such leftovers cannot be proved until the project provides them in plain C or patches them away. These
checks print reports and write no files.

`projects/NAME/fuzz.conf` (bash, optional) holds the project's defaults (`IMPORT_OPTS`, put before the command
line's options) and the build of the original targets for `qp fidelity`.

## The semantics mapping

The theorem (`harness_safe`, VST over CompCert's Clight) rules out undefined behaviour, and a failing `qp_assert`
is undefined behaviour. libFuzzer's crashes map as follows:

| libFuzzer reports | in the law | by |
|---|---|---|
| `abort()` (deadly signal), `FUZZ_ASSERT`/`CHECK` macros ending in `abort` | `qp_assert(0)` | the shim's `abort()` macro |
| `assert()` failure (glibc: `__assert_fail`), also in the library (lz4 with `LZ4_DEBUG=1`) | `qp_assert(0)` | the shim's `__assert_fail`, for every unit |
| `exit()`/`_Exit()` during the run ("fuzz target exited") | `qp_assert(0)` | the shim's macros |
| ASan: out-of-bounds access, use after free, double/invalid free, stack-use-after-return | undefined behaviour in CompCert's memory model | `harness_safe` |
| UBSan: shift out of range, division by zero, null dereference, misaligned access, float-to-int overflow, unreachable | undefined behaviour in CompCert's semantics | `harness_safe` |
| UBSan: signed integer overflow | defined in CompCert (it wraps), but VST's type checks require its absence (`tc_nosignedover`): a law with a reachable signed overflow cannot be proved | VST |
| ASan: `calloc` size overflow | `qp_assert(0)` | the shim's `calloc` |
| `-malloc_limit_mb` (default `-rss_limit_mb`, 2048 MiB): `malloc(n)` with `n >= limit` | `qp_assert(0)` (policy `limit`) | the shim's `malloc` |
| LeakSanitizer (on by default) | `qp_assert(qp_fuzz_live == 0)` at the end (`--leaks`, the default) | a count of live blocks |
| "fuzz target overwrites its const input" | `qp_assert(memcmp(copy, data, n) == 0)` (`--const-input full`, the default) | the driver |
| the return value (0, or -1: do not add to the corpus) | ignored | the driver |
| timeout, stack overflow, RSS above `-rss_limit_mb` | not covered | "Not covered" |

Everything the translation adds is plain C on top of the framework's primitives, compiled into the law and verified
with it. Nothing is added to `quickproof.h`, `Env.v` or `Contract.v`, and no axiom.

### The shim (`tools/fuzz/libfuzzer_env.h`)

- Crashes. `abort()`, `exit()`, `_Exit()` and glibc's assertion handler `__assert_fail` call `qp_fuzz_crash()`,
  which is `qp_assert(0)`. A libc whose assertion handler has another name needs the same one-line function.
- Allocation. In the target's code, `malloc`, `calloc` and `free` apply the allocation policy and count live
  blocks; the driver's own buffers use `qp_fuzz_raw_malloc`, the framework's `malloc` without policy. Library code
  reaches the policy through `--alloc-hook NAME=malloc|calloc|free`, which defines `NAME` as the target's
  allocator (lz4: `-DLZ4_USER_MEMORY_FUNCTIONS` in `quickproof.conf`, and `LZ4_malloc`, `LZ4_calloc`, `LZ4_free`).
  Library allocations that bypass every hook get the framework's `malloc`, which may return NULL. There the law is
  stronger than the fuzzer, and a target that treats such a NULL as a crash makes the law false. `realloc` is not
  provided (it needs the old size); the cone check reports it.
- Output (`printf`, `fprintf`, `puts`, `fputs`, `fputc`, `putc`, `putchar`, `fflush`, `perror`, `fwrite`) is
  dropped, since libFuzzer does not look at it. The calls are replaced by a function that returns 0 (`fwrite`: its
  count), and their arguments are not evaluated, so an argument with a side effect or with undefined behaviour is
  not seen. Other I/O (`fopen`, `read`, `getenv`, ...) is not provided.

### Allocation failure

With ASan, libFuzzer in practice lets an allocation succeed or reports the run. VST's `malloc` may return NULL on
any call. The `--alloc` policies:

- `limit` (the default): a request of `--malloc-limit-mb` MiB or more is a crash, and every smaller request
  succeeds by assumption (`qp_assume(p != NULL)`). It is the most faithful policy and the strongest. A law proved
  under `limit` implies the same law under `assume` and proves that no single allocation reaches 2 GiB. Without
  `--max-len`, a target that allocates a buffer as large as its input is false under `limit` at `n >= 2^31`;
  libFuzzer cannot run such inputs either.
- `assume`: every allocation succeeds, whatever its size. Weaker; for targets whose allocations grow with the input
  when no length bound is wanted.
- `may-fail`: the framework's semantics; the target must handle NULL from every allocation. Most fuzz targets
  `FUZZ_ASSERT(p)` after `malloc`, so this law is usually false.

A `calloc` whose size overflows is a crash under `limit` and `assume`, and NULL under `may-fail`.

### Assumptions of the law beyond the fuzzer's

- Without `--max-len` the law covers every length up to `SIZE_MAX`, beyond libFuzzer's `-max_len` (4096 by
  default) and beyond what memory can hold. Fuzz targets often convert the size to `int` or allocate in proportion
  to it, so the unbounded law may be false for reasons that are defects of the harness rather than of the library.
  `--max-len N` adds `qp_assume(n <= N)`; inputs longer than `N` are then not covered.
- `LLVMFuzzerInitialize`, if defined, runs once before the first input with `argc = 1`,
  `argv = {"qp-fuzz-law", NULL}`. `--init` and `--no-init` force it on or off. Targets that read their own command
  line or environment see that dummy.
- By default the law is one call in a fresh process. `--stateful K` makes it 1 to K calls in one process, each
  with a fresh nondet input and buffer, while the target's static state persists (`--stateful unbounded`: any
  number). A crash that needs a particular history then becomes part of the law.
- `--leaks` (the default) requires every block the target allocates through the shim to be freed by the end of the
  run. This is stronger than LeakSanitizer, which reports only unreachable blocks, so a target that keeps a block
  reachable on purpose (a cache, the state of `LLVMFuzzerInitialize`) needs `--no-leaks`.
- `--const-input full` (the default) requires the target not to modify its input. libFuzzer compares only the first
  and last 32 bytes of inputs longer than 64 bytes (`LooseMemeq`); `loose` is that check, and `off` drops it.
- The law runs the code in the configuration of `quickproof.conf`, which must reproduce the oracle flags of the
  upstream fuzz build (`NDEBUG`, `LZ4_DEBUG=1`, `FUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION`, ...), plus the
  project's safe configuration for VST and its idiom patch. The fidelity check sees both differences.

### Not covered

- The theorem is partial correctness, so a target that loops forever on some input satisfies its law.
- CompCert's stack is unbounded, and the cumulative RSS limit is not modelled (only single requests, policy
  `limit`).
- The importer refuses C++ targets (`.cc`, `FuzzedDataProvider`, `<fuzzer/...>`), since VST and CompCert are C
  only.
- Threads, signals, `setjmp`, `realloc`, `getenv` and I/O other than the dropped output have no plain-C model; the
  cone check names them.
- Custom mutators, `LLVMFuzzerCustomCrossOver`, dictionaries and options files change what the fuzzer tries, not
  what counts as a crash; the law ranges over all inputs anyway.
- Some sanitizer findings have no counterpart. Signed overflow is defined in CompCert (VST still rejects it, see the
  table), and the interpreter does not check it. An out-of-bounds pointer (`-fsanitize=pointer-overflow`) is
  defined in CompCert until it is used.

The law is stricter than the fuzzer where CompCert is stricter than ISO C (comparing a one-past-the-end pointer
with a pointer into another object), where it reads memory the sanitizers do not track (copying uninitialised
bytes is undefined in CompCert, like MSan), and where VST's type checks reject defined code. Such a stop is a
finding, or an idiom for the project's patch.

### A fuzz target is a weak law

A fuzz target's oracle is "no crash" plus whatever the target checks itself. lz4's `round_trip` target compares
the decompressed data with the input, so its law is a functional property; its `decompress` target checks nothing,
so its law is memory safety and the library's assertions only. Once a law is imported and checked, strengthen it
([HARNESSES.md](HARNESSES.md)): exact results against a reference, error codes, frames, state models. A
strengthened law is a new harness. The generated file is regenerated byte for byte and must not be edited; it
stays as the record of what upstream's own fuzzing claims.

## Determinism

The output is a function of the target and support files at the pinned commit (their sha256 are in the header),
the options (the header's `command:` and `options:` lines), the shim (its sha256 in the header) and `FUZZ_VERSION`
in `tools/qp` (version 2). It holds no time, host, user or random value, and no path but `UPSTREAM` as
`project.conf` writes it. Running the import again with the same inputs leaves every file unchanged
(`unchanged ...`).

`tools/fuzz/determinism.sh [--workspace DIR] NAME` regenerates every law of the project imported by `import-fuzz`
or `import-cbmc` from its own `command:` line, twice, in two fresh copies of the project in different temporary
workspaces, with different `TZ`, `LANG`, `PYTHONHASHSEED`, umask and working directory. It compares the outputs
byte for byte with each other and with the committed files. It only reads the project, and hand-written laws of a
mixed project are copied and not compared. `UPSTREAM` must be a URL or an absolute path, since a relative path
would resolve differently in the copies.

## The fidelity check

`tools/qp replay` runs a law on input files. The generated driver draws `nondet_size()` (the input length), then
`nondet_bytes(data, n)`, and with `--stateful` `nondet_u8()` ("one more call?"). A replay serves these draws from
the files: the length and the bytes of the next file, and 1 while another file follows. Natively this is
`tools/fuzz/replay_main.c`, linked with the law built as for `qp fuzz` (the verified configuration, the patch,
ASan/UBSan). Under CompCert's interpreter (`--interp`) it is a generated `GP_ENV` file with the bytes embedded, run
by `quickproof/tools/interp.sh`. A verdict is `pass`, `fail` (a failing `qp_assert`, a sanitizer report, a Stuck
state) or `not covered` (a false assumption, e.g. an input longer than `--max-len`).

`tools/qp fidelity` compares these verdicts with the original target's, built from unmodified upstream at `COMMIT`
and run as `./target FILE` (libFuzzer's reproduction mode; exit status 0 is `pass`). `fuzz.conf` gives the upstream
build (`ORIG_CC`, `ORIG_SANITIZE`, `ORIG_CFLAGS`, `ORIG_SOURCES`, `ORIG_RUN_OPTS`), by default
`clang -fsanitize=fuzzer,address,undefined -fno-sanitize-recover=all` with upstream's own flags.

The corpus comes from running the original targets as libFuzzer, a few minutes each. A healthy target passes its
whole corpus, so agreement on the corpus alone only shows that the law does not fail spuriously. `--fault
FILE|OLD|NEW` seeds a fault into the library (a textual replacement that must match exactly once, applied to both
the unmodified and the patched tree), rebuilds the original and the law, and compares again, so the check also
covers the failing side.

`projects/NAME/FIDELITY.md` gives, per law and per seeded fault, the inputs, those not covered, the failures of
each side and the agreement, natively and under the interpreter (a deterministic sample by size), and every
disagreement. The expected disagreements come from the interpreter's strictness (see "Not covered"), the project's
safe flags and idiom patch, `--leaks` (reachable blocks), `--const-input full` (bytes `LooseMemeq` does not compare)
and `--max-len`.

On bzip3's AFL++ harness
[`examples/fuzz-decompress.c`](https://github.com/iczelia/bzip3/blob/dce3573ac49837040f9b8c44c051f15162ac6a7a/examples/fuzz-decompress.c),
the imported law and the original target, built the upstream way, give the same verdict on all 62 inputs of a test
corpus. With a bounds check removed from the library, both fail on the same 10 inputs.

## Other engines and entry points

A preview in v0.1 (see the top of this page).

### Entry points: `--entry`, `--init`, `--cleanup`, `--define`

`--entry FN` names a target function `int FN(const uint8_t *, size_t)` other than `LLVMFuzzerTestOneInput`.
`--init FN` runs once before the first input, with `(&argc, &argv)` (`argc = 1`) if it takes `(int *, char ***)`,
or with no argument if it takes none; `--init` alone forces `LLVMFuzzerInitialize`. `--cleanup FN`, a function
without parameters, runs after the last input and before the leak check, so that state the initialisation
allocated can be freed. `--define NAME[=VALUE]` puts `#define NAME VALUE` at the top of the law, before any header,
for files that select their libFuzzer side by a macro. The provenance records all of them.

| project | target file | options |
|---|---|---|
| OpenSSL | `fuzz/asn1.c` (and the others) | `--entry FuzzerTestOneInput --init FuzzerInitialize --cleanup FuzzerCleanup` |
| Tor | `src/test/fuzz/fuzz_http.c` (and the others) | `--entry fuzz_main --init fuzz_init --cleanup fuzz_cleanup` |

`qp fidelity` links the original of such a target with the project's own driver (`ORIG_SOURCES`, e.g. OpenSSL's
`fuzz/driver.c`), as upstream builds it.

### AFL++ persistent mode: `--style afl`

An AFL++ harness has its own `main`, which reads test cases from AFL++'s buffer in a loop:

```c
__AFL_FUZZ_INIT();
int main(void) {
    __AFL_INIT();
    unsigned char *buf = __AFL_FUZZ_TESTCASE_BUF;
    while (__AFL_LOOP(10000)) {
        int len = __AFL_FUZZ_TESTCASE_LEN;
        if (len < 8) continue;
        target_function(buf, len);
    }
    return 0;
}
```

The law compiles the file as is, its `main` renamed (and called with `argc = 1` if it takes arguments), after
`tools/fuzz/afl_env.h`, which defines afl-cc's macros with their meaning in one AFL++ process:

| AFL++ | in the law |
|---|---|
| `__AFL_FUZZ_INIT()`, `__AFL_INIT()`, `__AFL_COVERAGE*`, `__AFL_LEAK_CHECK()` | nothing |
| `__AFL_HAVE_MANUAL_CONTROL`, `__AFL_COMPILER` | defined, so the AFL++ side of the file is compiled |
| `__AFL_FUZZ_TESTCASE_BUF` | one buffer for the whole run, 1 MiB as AFL++'s (`--max-len N`: N bytes), zeroed once |
| `__AFL_LOOP(N)` | true for the first input only; with `--stateful K`, true at a nondet choice for up to K inputs and at most N |
| each input | a nondet length n up to the buffer's size and n nondet bytes at the buffer's start; beyond them, zeros or bytes of earlier inputs |
| `__AFL_FUZZ_TESTCASE_LEN` | the length of the current input (before any `__AFL_LOOP`, it fetches the input) |
| `exit()`, `_Exit()` | the end of the run, not a crash, since AFL++ reports signals only |
| `abort()`, a failing `assert()`, sanitizer reports | crashes, as with libFuzzer |

A read past the input but inside the buffer is not a failure, as under AFL++, and the claim says so. This is weaker
than the libFuzzer import, whose buffer has exactly n bytes.

The defaults follow the engine: `--alloc assume` (AFL++ sets no memory limit by default), `--no-leaks` (AFL++
detects leaks only when asked) and `--const-input off` (the buffer is writable). Each can be given explicitly. A
harness that reads its input itself (`read(0, ...)`, `fread` on `stdin`, a file named by `argv`) is refused, since
the importer has no model of standard input and files. Fallback definitions for builds without afl-cc
(`#ifndef __AFL_FUZZ_TESTCASE_LEN ... read(0, ...) ... #endif`) do not count, since the shim defines those macros.

`qp fidelity` builds the original without AFL++, with clang, `-fsanitize=address,undefined` and
`tools/fuzz/afl_repro.h`: the macros as afl-cc defines them outside afl-fuzz (the test case read from standard
input into a 1 MiB buffer, `__AFL_LOOP` true once). With `ORIG_CC=afl-clang-fast` in `fuzz.conf`, afl-cc's own
definitions are used instead. It runs `./target < FILE` and counts only a signal as a failure.

### honggfuzz: `--style honggfuzz`

A honggfuzz persistent-mode harness calls `HF_ITER(&buf, &len)` (or `HonggfuzzFetchData`) in an endless loop. The
law compiles it as is, its `main` renamed, after `tools/fuzz/honggfuzz_env.h`. The first call of `HF_ITER` hands
out a fresh buffer of exactly `len` nondet bytes, and the next call, like `exit()`, ends the run without error
(`--stateful K`: up to K inputs). The definition of `HF_ITER` takes the harness's own declaration (`uint8_t **` or
`const uint8_t **`). Under CompCert's interpreter that end is a divergence (the theorem's `qp_assume(0)`), so
`qp interp` and `qp replay --interp` give no verdict on a run that reaches it; they still stop at undefined
behaviour before it.

honggfuzz also runs libFuzzer targets (`-P`), and there a return value other than 0 is fatal. So
`--style honggfuzz` on a file without `HF_ITER` imports it as a libFuzzer target whose law also asserts that the
return value is 0. `qp fidelity` links the original of an `HF_ITER` harness with `tools/fuzz/hfuzz_repro.c` in place
of libhfuzz: the first call returns standard input in a buffer of exactly its length, the next one exits with
status 0.

## Adding a project

Imported laws join the project's other laws in one `suite`. Per-law linking (`LINK=per-law`, the default of
`qp new`; [LINKING.md](LINKING.md)) keeps the fuzz cone out of the other laws' programs.

1. Run `tools/qp new NAME URL`, with the targets and their support files in `CODE` and the library units with the
   fuzz build's oracle flags in `quickproof.conf`.
2. In `fuzz.conf`, set `IMPORT_OPTS` (support files, allocation hooks) and the original build.
3. Run `tools/qp import-fuzz NAME TARGET.c` per target, fix what the cone check reports (idiom patches, allocation
   hooks), and run it once with `--contract`.
4. Write `env/<law>.c` for inputs that reach deep (valid formats, the target's parameter bytes) when the project's
   `env.c` serves its other laws; `qp fuzz`, `interp` and `mutants` use it instead of `env.c` for that law.
5. Run `tools/qp check NAME`, make a corpus, and run `tools/qp fidelity NAME --corpus DIR --interp N --fault ...`
   and `tools/fuzz/determinism.sh NAME`.
6. Strengthen the laws, then prove them (`tools/qp assemble`, and `tools/qp verify` on the result).

## Other formats (future work)

CBMC harnesses ([IMPORT-CBMC.md](IMPORT-CBMC.md)) and SV-COMP tasks ([SVCOMP.md](SVCOMP.md)), both previews in
v0.1, use the same scheme: a deterministic translation, a plain-C shim, a replay check against the original tool.
KLEE would fit (`klee_make_symbolic(p, n)` is `nondet_bytes`, and `.ktest` files are the replay inputs), and so
would theft, whose shrunk counterexamples would replay as inputs.
