#!/usr/bin/env bash
# tests/qp/libfuzzer.sh: `qp fuzz --libfuzzer` (tools/fuzz/law_libfuzzer.c) on a toy workspace, offline.  Needs gcc
# with ASan/UBSan, clang with libFuzzer and git (skipped without clang's libFuzzer); not the Coq toolchain.
# Writes only in a temporary directory.  Prints one ok/FAIL line per check; exit 0 iff all pass.
#
# The upstream is the framework's toy library (tests/perlaw/lib).  Laws:
#   law_count   (tests/perlaw) true: runs clean;
#   law_false   false for counters above 1000: the fuzzer finds it with --nondet direct, the crash replays in the
#               fuzzer binary and in a fresh native process (--replay); with --nondet env the project's env.c
#               draws only u32 values below 5, and the law runs clean;
#   law_state   every run must start from the program's initial state: a global set by the previous run, or a
#               1 MiB block kept in a global (never freed: freed by the driver between inputs), would fail it or
#               exhaust -rss_limit_mb; exit() ends a run normally;
#   law_fresh   draws until a value is not 0: it ends on the empty input too (zeros, then a pseudo-random tail).
set -euo pipefail
GP=$(cd "$(dirname "$0")/../.." && pwd)
QP=$GP/tools/qp
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   qp: $*"; }
bad() { echo "FAIL qp: $*"; fails=$((fails + 1)); }
printf 'int LLVMFuzzerTestOneInput(const char *d, unsigned long n) { return 0; }\n' > "$T/lf.c"
if ! clang -fsanitize=fuzzer,address,undefined "$T/lf.c" -o "$T/lf" > /dev/null 2>&1; then
  echo "skip qp: fuzz --libfuzzer (no clang with libFuzzer)"; exit 0
fi
G=(git -c user.name=qp-test -c user.email=qp-test@localhost -c init.defaultBranch=main)
unset QP_WORKSPACE QP_FRAMEWORK_DIR QP_TEMPLATES QP_OPAM_SWITCH QP_FRAMEWORK_URL
export QP_SITE_CONF=/dev/null QP_CACHE=$T/cache DEBUGINFOD_URLS=

mkdir -p "$T/upstream/lib"
cp "$GP"/tests/perlaw/lib/* "$T/upstream/lib/"
(cd "$T/upstream" && "${G[@]}" init -q && "${G[@]}" add -A && "${G[@]}" commit -qm v1.0)
P=$T/ws/projects/toy
mkdir -p "$P/harness"
cat > "$P/project.conf" <<EOF
UPSTREAM=$T/upstream
COMMIT=$(git -C "$T/upstream" rev-parse HEAD)
FRAMEWORK=
LOGICAL=Toy
CODE="lib"
PATCH=""
BROKEN="law_false"
EOF
printf 'INC=(-Ilib)\nDEFS=()\nLINK=per-law\nUNITS=(\n  "lib/counter.c=src/counter"\n  "lib/log.c=src/log"\n)\n' > "$P/quickproof.conf"
cp "$GP/tests/perlaw/harness/law_count.c" "$P/harness/"
cat > "$P/harness/law_false.c" <<'EOF'
/* Law law_false (false): counter_inc on a counter below any bound leaves it at most at 1000. */
#include "quickproof.h"
#include "counter.h"

int main(void)
{
	struct counter c;
	c.n = nondet_u32();
	c.max = nondet_u32();
	gp_assume(c.n < c.max);
	counter_inc(&c);
	gp_assert(counter_get(&c) <= 1000);
	return 0;
}
EOF
cat > "$P/harness/law_state.c" <<'EOF'
/* Law law_state: every run starts from the program's initial state. */
#include <stdlib.h>
#include "quickproof.h"

static unsigned runs;
static unsigned char *kept;

int main(void)
{
	gp_assert(runs == 0);
	gp_assert(kept == NULL);
	runs = runs + 1;
	kept = malloc(1 << 20);
	if (kept != NULL)
		kept[0] = 1;
	if (nondet_u8() == 1)
		exit(0);
	return 0;
}
EOF
cat > "$P/harness/law_fresh.c" <<'EOF'
/* Law law_fresh: a value drawn again until it is not 0 is not 0. */
#include "quickproof.h"

int main(void)
{
	unsigned x;
	do
		x = nondet_u32();
	while (x == 0);
	gp_assert(x != 0);
	return 0;
}
EOF
cat > "$P/env.c" <<'EOF'
/* The toy's value distributions: u32 values below 5. */
#include <stdint.h>
extern uint64_t quickproof_rnd(void);
uint32_t nondet_u32(void) { return (uint32_t) (quickproof_rnd() % 5); }
EOF
Q=("$QP" --workspace "$T/ws")
run() {   # run LOG CMD...: output in $T/LOG.log, status in $rc
  local log=$1; shift
  if "$@" > "$T/$log.log" 2>&1; then rc=0; else rc=$?; fi
}

run direct "${Q[@]}" fuzz toy law_count law_false law_state --libfuzzer --nondet direct --seconds 15 --out "$T/direct"
if [ $rc = 1 ] && grep -q '^law_count .* clean$' "$T/direct.log" && grep -q '^law_state .* clean$' "$T/direct.log" &&
   grep -q '^law_false .* CRASH law_false/crashes/crash-[0-9a-f]*: FAIL: gp_assert at harness_main law_false.c:12.*; native replay: FAIL: gp_assert$' "$T/direct.log"; then
  ok "fuzz --libfuzzer --nondet direct: the false law crashes (and the native replay agrees), the true ones run clean"
else bad "fuzz --libfuzzer --nondet direct"; cat "$T/direct.log"; fi
if grep -q 'state restored per input' "$T/direct.log" && grep -Eq 'law_state .*' "$T/direct.log" &&
   grep -A1 '^law_state' "$T/direct.log" | grep -Eq 'ended by exit [1-9]'; then
  ok "fuzz --libfuzzer: globals and heap reset per input; exit() ends a run normally"
else bad "fuzz --libfuzzer: state reset / exit tally"; cat "$T/direct.log"; fi

if [ "$(readlink "$T/direct/law_count/bin/law_count")" = ../fuzz ] && [ "$(readlink "$T/direct/law_count/native/law_count")" = ../replay ]; then
  ok "fuzz --libfuzzer: the binaries are run under the law's name (bin/LAW, native/LAW)"
else bad "fuzz --libfuzzer: law-named links"; ls -la "$T/direct/law_count" "$T/direct/law_count/bin"; fi

run noreset env QP_LF_NO_RESET=1 "$T/direct/law_state/bin/law_state" -runs=1000 -artifact_prefix="$T/" "$T/direct/law_state/corpus"
if [ $rc != 0 ] && grep -q 'qp-libfuzzer: gp_assert failed' "$T/noreset.log"; then
  ok "fuzz --libfuzzer: without the reset (QP_LF_NO_RESET=1) law_state fails on its second input"
else bad "fuzz --libfuzzer: law_state passes without the reset"; tail -5 "$T/noreset.log"; fi

crash=$(ls "$T"/direct/law_false/crashes/crash-* 2>/dev/null | head -1)
run replay "${Q[@]}" fuzz toy law_false --libfuzzer --nondet direct --out "$T/direct" --replay "$crash"
if [ $rc = 1 ] && grep -q 'libFuzzer build: FAIL: gp_assert at harness_main law_false.c' "$T/replay.log" &&
   grep -q 'native replay:   FAIL: gp_assert' "$T/replay.log"; then
  ok "fuzz --libfuzzer --replay: the crash input replays (fuzzer binary and a fresh native process)"
else bad "fuzz --libfuzzer --replay"; cat "$T/replay.log"; fi
printf '' > "$T/empty"
run replay0 "${Q[@]}" fuzz toy law_false --libfuzzer --nondet direct --out "$T/direct" --replay "$T/empty"
if [ $rc = 0 ] && grep -q 'libFuzzer build: not covered (gp_assume)' "$T/replay0.log" &&
   grep -q 'native replay:   not covered (gp_assume)' "$T/replay0.log"; then
  ok "fuzz --libfuzzer --replay: the empty input draws zeros, which the law's assume rejects"
else bad "fuzz --libfuzzer --replay of the empty input"; cat "$T/replay0.log"; fi

run fresh "${Q[@]}" fuzz toy law_fresh --libfuzzer --nondet direct --out "$T/direct" --replay "$T/empty"
if [ $rc = 0 ] && grep -q 'libFuzzer build: pass' "$T/fresh.log" && grep -q 'native replay:   pass' "$T/fresh.log"; then
  ok "fuzz --libfuzzer: past the end of the input, zeros then a pseudo-random tail (a redraw loop ends)"
else bad "fuzz --libfuzzer: redraw loop on an exhausted input"; cat "$T/fresh.log"; fi

run env "${Q[@]}" fuzz toy law_false --libfuzzer --nondet env --seconds 8 --out "$T/env"
if [ $rc = 0 ] && grep -q '^law_false .* clean$' "$T/env.log"; then
  ok "fuzz --libfuzzer --nondet env: the project's env.c shapes the input (u32 below 5: law_false holds)"
else bad "fuzz --libfuzzer --nondet env"; cat "$T/env.log"; fi

[ "$fails" -eq 0 ]
