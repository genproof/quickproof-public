#!/usr/bin/env bash
# tests/qp/fuzz_engines.sh: `tools/qp import-fuzz` on targets of other engines and entry points, offline.  Needs the
# toolchain in PATH (CompCert 3.15), gcc with ASan/UBSan and git; clang for `qp fidelity` (skipped without it).
# Writes only in a temporary directory.  Prints one ok/FAIL line per check; exit 0 iff all pass.
#
# The upstream is a local git repository made of the toy library (tests/perlaw/lib) and the targets of
# tests/qp/upstream, written for these tests.  Two projects:
#   engines  --style afl (AFL++ persistent mode: afl_counter.c, also --stateful 3) and --style honggfuzz (HF_ITER:
#            hf_counter.c; a libFuzzer target whose non-zero return is fatal under honggfuzz: hf_entry.c); the
#            refusals (a harness that reads stdin, --style afl on a libFuzzer target, --entry on a harness with its
#            own main); native runs; replay natively and under the interpreter; determinism.sh; fidelity against the
#            originals built with the reproduction stubs (tools/fuzz/afl_repro.h, hfuzz_repro.c), with a seeded fault;
#   entries  --entry/--init/--cleanup: an OpenSSL-style target (FuzzerTestOneInput, FuzzerInitialize(&argc, &argv),
#            FuzzerCleanup, which the leak check needs) and a Tor-style one (fuzz_main, fuzz_init(void), a static
#            fuzz_cleanup, --define); replay; determinism.sh.
set -uo pipefail
GP=$(cd "$(dirname "$0")/../.." && pwd)
QP=$GP/tools/qp
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
touch "$T/start"
fails=0
ok() { echo "ok   engines: $*"; }
bad() { echo "FAIL engines: $*"; fails=$((fails + 1)); }
G=(git -c user.name=qp-test -c user.email=qp-test@localhost -c init.defaultBranch=main)
unset QP_WORKSPACE QP_TEMPLATES QP_OPAM_SWITCH QP_FRAMEWORK_URL
export QP_SITE_CONF=/dev/null QP_CACHE=$T/cache QP_FRAMEWORK_DIR=$GP QP_JOBS=2 DEBUGINFOD_URLS= PYTHONDONTWRITEBYTECODE=1
run() {   # run LOG CMD...: the command's output in $T/LOG.log, its exit status in $rc
  local log=$1; shift
  if "$@" > "$T/$log.log" 2>&1; then rc=0; else rc=$?; fi
}
has() { grep -q -- "$2" "$T/$1.log"; }

# the upstream: the toy library and the targets
mkdir -p "$T/upstream/lib" "$T/upstream/fuzz"
cp "$GP"/tests/perlaw/lib/* "$T/upstream/lib/"
cp "$GP"/tests/qp/upstream/*.c "$T/upstream/fuzz/"
(cd "$T/upstream" && "${G[@]}" init -q && "${G[@]}" add -A && "${G[@]}" commit -qm v1.0)
UP=$(git -C "$T/upstream" rev-parse HEAD)
mkproject() {   # mkproject NAME: a project on the toy library (an include guard for tools/interp.sh, as in e2e.sh)
  local P=$T/ws/projects/$1
  mkdir -p "$P/harness" "$P/patch"
  printf 'UPSTREAM=%s\nCOMMIT=%s\nFRAMEWORK=\nLOGICAL=%s\nCODE="lib fuzz"\nPATCH="sh patch/guard.sh"\n' "$T/upstream" "$UP" "$1" \
    > "$P/project.conf"
  printf 'INC=(-Ilib)\nDEFS=()\nLINK=per-law\nUNITS=(\n  "lib/counter.c=src/counter"\n  "lib/log.c=src/log"\n  "$GP/libc/libc.c=src/libc"\n  "$GP/libc/malloc_unit.c=src/malloc"\n)\n' \
    > "$P/quickproof.conf"
  printf 'ORIG_SOURCES=(lib/counter.c lib/log.c)\nORIG_CFLAGS=(-Ilib)\n' > "$P/fuzz.conf"
  cat > "$P/patch/guard.sh" <<'EOF'
set -e
f=lib/counter.h
{ echo '#ifndef COUNTER_H'; echo '#define COUNTER_H'; cat "$f"; echo '#endif'; } > "$f.new"
mv "$f.new" "$f"
EOF
}
mkproject engines
mkproject entries
E=$T/ws/projects/engines
N=$T/ws/projects/entries
Q=("$QP" --workspace "$T/ws")

# ---- engines: imports
run afl "${Q[@]}" import-fuzz engines fuzz/afl_counter.c --style afl --max-len 64
h=$E/harness/afl_counter.c
if [ $rc = 0 ] && has afl 'ok: only the framework environment is external, no VST blocker in the cone' &&
   grep -q '^ \*   command:        tools/qp import-fuzz engines fuzz/afl_counter.c --law afl_counter --style afl --max-len 64 --alloc assume --no-leaks --const-input off$' "$h" &&
   grep -q 'style=afl-main$' "$h" && grep -q '^#define QP_AFL_MAX ((size_t) 64)$' "$h" && grep -q '^#define QP_AFL_STATEFUL 0$' "$h" &&
   grep -q '^#include "fuzz/afl_env.h"$' "$h" && grep -q '^#define main qp_fuzz_target_main$' "$h" && grep -q 'qp_afl_setup();' "$h" &&
   grep -q '^ \*   style-shim:     harness/fuzz/afl_env.h sha256 ' "$h" && head -1 "$E/harness/fuzz/afl_env.h" | grep -q 'a copy of tools/fuzz/afl_env.h' &&
   grep -q 'Law imported from the AFL++ persistent-mode harness `fuzz/afl_counter.c`' "$h"; then
  ok "import --style afl: the harness's main renamed, AFL++'s buffer and loop from afl_env.h, the engine's defaults; cone clean"
else bad "import --style afl"; cat "$T/afl.log"; head -30 "$h"; fi
run afl3 "${Q[@]}" import-fuzz engines fuzz/afl_counter.c --style afl --law afl_counter3 --stateful 3 --max-len 64 --no-check
if [ $rc = 0 ] && grep -q '^#define QP_AFL_STATEFUL 3$' "$E/harness/afl_counter3.c"; then ok "import --style afl --stateful 3"
else bad "import --style afl --stateful 3"; cat "$T/afl3.log"; fi
run hf "${Q[@]}" import-fuzz engines fuzz/hf_counter.c --style honggfuzz --max-len 64
h=$E/harness/hf_counter.c
if [ $rc = 0 ] && has hf 'ok: only the framework environment is external, no VST blocker in the cone' &&
   grep -q '^#define QP_HF_ITER_CONST 0$' "$h" && grep -q '^#define QP_HF_MAX_LEN 64$' "$h" && grep -q '^#include "fuzz/honggfuzz_env.h"$' "$h" &&
   grep -q 'style=honggfuzz-main$' "$h" && grep -q 'Law imported from the honggfuzz persistent-mode harness `fuzz/hf_counter.c`' "$h"; then
  ok "import --style honggfuzz (HF_ITER declared with uint8_t **): an exact buffer per input; cone clean"
else bad "import --style honggfuzz"; cat "$T/hf.log"; head -30 "$h"; fi
run hfe "${Q[@]}" import-fuzz engines fuzz/hf_entry.c --style honggfuzz --no-check
run hfl "${Q[@]}" import-fuzz engines fuzz/hf_entry.c --law hf_entry_libfuzzer --no-check
if grep -q 'qp_assert(LLVMFuzzerTestOneInput(data, n) == 0);' "$E/harness/hf_entry.c" && grep -q 'style=honggfuzz-entry$' "$E/harness/hf_entry.c" &&
   grep -q '^	(void) LLVMFuzzerTestOneInput(data, n);$' "$E/harness/hf_entry_libfuzzer.c"; then
  ok "import --style honggfuzz of a libFuzzer target: the return value must be 0 (it is ignored without --style)"
else bad "honggfuzz entry mode"; cat "$T/hfe.log" "$T/hfl.log"; fi
for e in "stdin|fuzz/afl_stdin.c --style afl|reads its input itself" \
         "lf|fuzz/counter_fuzzer.c --style afl|is not an AFL++ persistent or deferred-mode harness" \
         "entry|fuzz/afl_counter.c --style afl --law x --entry LLVMFuzzerTestOneInput|--entry, --init and --cleanup are for entry-function targets"; do
  IFS='|' read -r tag args why <<< "$e"
  # shellcheck disable=SC2086
  run "ref-$tag" "${Q[@]}" import-fuzz engines $args --no-check
  if [ $rc != 0 ] && has "ref-$tag" "$why"; then ok "refused: $why"; else bad "refusal $tag"; cat "$T/ref-$tag.log"; fi
done

# ---- engines: native runs, replay, determinism
run fz "${Q[@]}" fuzz engines afl_counter afl_counter3 hf_counter -n 100
if has fz '^afl_counter  *patched  *ok (100 runs)' && has fz '^afl_counter3  *patched  *ok (100 runs)' &&
   grep -E '^hf_counter +patched +(ok|FAILED)' "$T/fz.log" > /dev/null; then
  ok "qp fuzz: the AFL++ and honggfuzz laws build and run natively"
else bad "qp fuzz"; cat "$T/fz.log"; fi
C=$T/corpus; mkdir -p "$C/afl_counter" "$C/hf_counter"
for d in afl_counter hf_counter; do
  printf '\005\003' > "$C/$d/count"; printf '\001' > "$C/$d/short"; printf '\377\000' > "$C/$d/exit"
  printf '\005\003\376' > "$C/$d/abort-hf"; head -c 100 /dev/zero | tr '\0' a > "$C/$d/long"
done
run rafl "${Q[@]}" replay engines afl_counter "$C/afl_counter"
run rhf "${Q[@]}" replay engines hf_counter "$C/hf_counter"
if has rafl '^afl_counter, native (patched): not covered 1, pass 4$' && has rhf '^hf_counter, native (patched): fail 1, not covered 1, pass 3$' &&
   has rhf '^fail  *abort-hf'; then
  ok "replay: AFL++ law passes (exit is not a crash), the honggfuzz law fails where the harness aborts, long inputs not covered"
else bad "replay"; cat "$T/rafl.log" "$T/rhf.log"; fi
run rseq "${Q[@]}" replay engines afl_counter3 "$C/afl_counter/count" "$C/afl_counter/short" "$C/afl_counter/count" --sequence
run rint "${Q[@]}" replay engines afl_counter "$C/afl_counter/count" "$C/afl_counter/exit" --interp --timeout 20
if has rseq '^afl_counter3, native (patched): pass 1$' && has rint '^afl_counter, interpreter: pass 1, timeout 1$'; then
  ok "replay: three inputs in one AFL++ process (--stateful 3); under the interpreter (exit ends the run: no verdict)"
else bad "replay --sequence / --interp"; cat "$T/rseq.log" "$T/rint.log"; fi
run hfr "${Q[@]}" replay engines hf_entry "$C/afl_counter/count"
printf 'R\001' > "$T/R"
run hfr2 "${Q[@]}" replay engines hf_entry "$T/R"
run hfr3 "${Q[@]}" replay engines hf_entry_libfuzzer "$T/R"
if has hfr '^hf_entry, native (patched): pass 1$' && has hfr2 '^hf_entry, native (patched): fail 1$' &&
   has hfr3 '^hf_entry_libfuzzer, native (patched): pass 1$'; then
  ok "replay: the return value 1 fails the law under honggfuzz's rule, not under libFuzzer's"
else bad "replay of honggfuzz entry mode"; cat "$T/hfr.log" "$T/hfr2.log" "$T/hfr3.log"; fi
run det "$GP/tools/fuzz/determinism.sh" --workspace "$T/ws" engines
if [ $rc = 0 ] && has det 'run a = b: identical (9 files)' && has det 'run a = committed: identical (9 files)'; then
  ok "determinism.sh: the AFL++ and honggfuzz laws regenerate byte for byte"
else bad "determinism.sh engines"; cat "$T/det.log"; fi

# ---- engines: fidelity against the originals (reproduction stubs: stdin, signals only)
if command -v clang > /dev/null; then
  run fid "${Q[@]}" fidelity engines afl_counter hf_counter --corpus "$C" --fault 'lib/counter.c|c->n = c->n + 1;|c->n = c->n + 2;'
  md=$E/FIDELITY.md
  if [ $rc = 0 ] && grep -q '^| `afl_counter` | 5 | 1 | 0 | 0 | \*\*4/4\*\* |$' "$md" && grep -q '^| `hf_counter` | 5 | 1 | 1 | 1 | \*\*4/4\*\* |$' "$md" &&
     grep -q '^| 0 | `afl_counter` | 2 | 2 | \*\*4/4\*\* |$' "$md" && grep -q '^| 0 | `hf_counter` | 2 | 2 | \*\*4/4\*\* |$' "$md" &&
     grep -A2 '^## Disagreements' "$md" | grep -q '^none$' && grep -q 'tools/fuzz/afl_repro.h' "$md"; then
    ok "fidelity: the AFL++ and honggfuzz laws agree with their originals (stdin, signals), also under a seeded fault"
  else bad "fidelity engines"; cat "$T/fid.log" "$md"; fi
else echo "skip engines: fidelity (no clang)"; fi

# ---- entries: --entry, --init, --cleanup, --define
run ossl "${Q[@]}" import-fuzz entries fuzz/ossl_counter.c --entry FuzzerTestOneInput --init FuzzerInitialize --cleanup FuzzerCleanup --max-len 16
h=$N/harness/ossl_counter.c
if [ $rc = 0 ] && has ossl 'ok: only the framework environment is external, no VST blocker in the cone' &&
   grep -q '^	(void) FuzzerInitialize(&qp_fuzz_argc, &qp_fuzz_argvp);$' "$h" && grep -q '^	(void) FuzzerTestOneInput(data, n);$' "$h" &&
   grep -q '^	(void) FuzzerCleanup();$' "$h" &&
   grep -q -- '--law ossl_counter --entry FuzzerTestOneInput --max-len 16 --alloc limit --malloc-limit-mb 2048 --leaks --init FuzzerInitialize --cleanup FuzzerCleanup --const-input full$' "$h" &&
   grep -q 'FuzzerTestOneInput, with an input of at most 16 bytes' "$h"; then
  ok "import --entry/--init/--cleanup (OpenSSL style: FuzzerInitialize(&argc, &argv), FuzzerCleanup before the leak check)"
else bad "import OpenSSL style"; cat "$T/ossl.log"; head -40 "$h"; fi
run osslnc "${Q[@]}" import-fuzz entries fuzz/ossl_counter.c --law ossl_nocleanup --entry FuzzerTestOneInput --init FuzzerInitialize --max-len 16 --no-check
run tor "${Q[@]}" import-fuzz entries fuzz/tor_counter.c --entry fuzz_main --init fuzz_init --cleanup fuzz_cleanup --define TOY_BOUND=10 --max-len 16
h=$N/harness/tor_counter.c
if [ $rc = 0 ] && grep -q '^#define TOY_BOUND 10$' "$h" && grep -q '^	(void) fuzz_init();$' "$h" && grep -q '^	(void) fuzz_cleanup();$' "$h" &&
   grep -q -- '--define TOY_BOUND=10$' "$h" && grep -q 'defines=TOY_BOUND=10$' "$h"; then
  ok "import --entry/--init/--cleanup (Tor style: fuzz_init(void), a static fuzz_cleanup) with --define"
else bad "import Tor style"; cat "$T/tor.log"; head -40 "$h"; fi
run refinit "${Q[@]}" import-fuzz entries fuzz/tor_counter.c --law x --entry fuzz_main --init nosuch --no-check
run refent "${Q[@]}" import-fuzz entries fuzz/tor_counter.c --law x --no-check
if has refinit '--init nosuch: fuzz/tor_counter.c does not define it' && has refent 'fuzz/tor_counter.c does not define LLVMFuzzerTestOneInput'; then
  ok "refused: an --init function the target does not define; a target without the entry function"
else bad "refusals of entries"; cat "$T/refinit.log" "$T/refent.log"; fi
CE=$T/corpus-e; mkdir -p "$CE"; printf '\005' > "$CE/small"; printf '\040' > "$CE/big"; printf '' > "$CE/empty"
run ro "${Q[@]}" replay entries ossl_counter "$CE"
run ronc "${Q[@]}" replay entries ossl_nocleanup "$CE/small"
run rt "${Q[@]}" replay entries tor_counter "$CE"
if has ro '^ossl_counter, native (patched): pass 3$' && has ronc '^ossl_nocleanup, native (patched): fail 1$' &&
   has rt '^tor_counter, native (patched): fail 1, pass 2$' && has rt '^fail  *big'; then
  ok "replay: the cleanup frees what the initialisation allocated (without it the leak check fails); the define takes effect"
else bad "replay entries"; cat "$T/ro.log" "$T/ronc.log" "$T/rt.log"; fi
run dete "$GP/tools/fuzz/determinism.sh" --workspace "$T/ws" entries
if [ $rc = 0 ] && has dete 'run a = committed: identical (5 files)'; then ok "determinism.sh: the entry-point laws regenerate byte for byte"
else bad "determinism.sh entries"; cat "$T/dete.log"; fi

new=$(find "$GP" -newer "$T/start" -type f -not -path '*/.git/*' -not -path "$GP/coq/*" | head)
if [ -z "$new" ]; then ok "nothing written in the framework checkout"; else bad "files written in the checkout: $new"; fi
[ "$fails" -eq 0 ]
