#!/usr/bin/env bash
# quickproof tools/fuzz_gate.sh HARNESS.c [RUNS [BUDGET [TIMEOUT]]] [-- EXTRA cc args]: the non-vacuity gate.
#
# Builds HARNESS.c natively with runtime/fuzz_driver.c (the same way as a native check, RECIPE step 3),
# runs the fuzzer in gate mode, and FAILS (nonzero exit) if some gp_assume accepts no input, or if no
# gp_assert is reached past the assumes -- i.e. the assumes make the harness vacuous or are too tight.
# It also prints the per-assume acceptance rate and per-assert reach count from the driver's tally.
#
# This is UNTRUSTED TOOLING and a QUALITY gate only: it does not enlarge the trusted base (coq/QuickProof,
# include/quickproof.h) and soundness rests only on the proofs.  It catches VACUITY, not weakness: whether
# an assume is the weakest it could be stays the spec-writer's call (human review, see docs/HARNESSES.md).
#
# EXTRA cc args (after `--`): extra units/includes/defs the harness needs (library .c files, -I, -D, and
# a project env .c defining the nondet_*).  For a self-contained harness none are needed.
set -euo pipefail
GP=$(cd "$(dirname "$0")/.." && pwd)
[ $# -ge 1 ] || { echo "usage: $0 HARNESS.c [RUNS [BUDGET [TIMEOUT]]] [-- EXTRA cc args]" >&2; exit 64; }
HARNESS=$1; shift
RUNS=2000; BUDGET=100000; TIMEOUT=10; EXTRA=()
POS=()
while [ $# -gt 0 ]; do
  if [ "$1" = "--" ]; then shift; EXTRA=("$@"); break; fi
  POS+=("$1"); shift
done
[ ${#POS[@]} -ge 1 ] && RUNS=${POS[0]}
[ ${#POS[@]} -ge 2 ] && BUDGET=${POS[1]}
[ ${#POS[@]} -ge 3 ] && TIMEOUT=${POS[2]}

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
CC=${CC:-cc}
CFLAGS=(-O0 -fno-delete-null-pointer-checks -I"$GP/include")
# -O0 -fno-delete-null-pointer-checks: keep the deliberate null store of a failed gp_assert (file header).
# -Dmain=harness_main renames only the harness's main, so the driver keeps its own (RECIPE step 3).
"$CC" "${CFLAGS[@]}" -Dmain=harness_main -c "$HARNESS" -o "$TMP/harness.o"
"$CC" "${CFLAGS[@]}" -c "$GP/runtime/fuzz_driver.c" -o "$TMP/driver.o"
"$CC" "${CFLAGS[@]}" "$TMP/harness.o" "$TMP/driver.o" "${EXTRA[@]}" -o "$TMP/fuzz"

echo "# fuzz_gate: $HARNESS  (runs=$RUNS budget=$BUDGET timeout=${TIMEOUT}s)"
set +e
GP_GATE=1 "$TMP/fuzz" "$RUNS" 1 "$BUDGET" "$TIMEOUT"
rc=$?
set -e
# fuzz_driver returns 2 when GP_GATE and the gate fails, 1 on a finding, 0 when clean and non-vacuous.
if [ "$rc" -eq 2 ]; then echo "GATE: FAIL (vacuous/over-tight assume)"; exit 1; fi
if [ "$rc" -ne 0 ]; then echo "GATE: inconclusive -- the run reported a finding (signal); fix it first"; exit "$rc"; fi
echo "GATE: PASS (non-vacuity witness found for every reached assert)"
