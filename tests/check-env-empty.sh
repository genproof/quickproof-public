#!/usr/bin/env bash
# quickproof tests/check-env-empty.sh: the regression test of nondet_bytes(NULL, 0) (called by tests/run.sh;
# also runs alone).  Needs the toolchain on PATH (for example, opam env) and gcc with ASan/UBSan.
#
# tests/EnvEmpty.v proves, against QuickProof.Env.nondet_bytes_spec, that a Clight call nondet_bytes(NULL, 0)
# is legal and keeps an unrelated cell, and that the non-NULL contract (any length, including 0) is
# unchanged.  tests/env_empty.c runs empty NULL, empty non-NULL and one-byte calls natively under ASan/UBSan
# (runtime/fuzz_driver.c) and under CompCert's interpreter (tools/interp.sh), ten seeds each: the drivers
# touch buf only for i < n.  Writes only in a temporary directory.  Exit 0 iff every step passes.
set -euo pipefail
GP_TEST_ROOT=$(cd "$(dirname "$0")/.." && pwd)
GP_TEST_TMP=$(mktemp -d)
trap 'rm -rf "$GP_TEST_TMP"' EXIT
cd "$GP_TEST_TMP"   # coqc writes .lia.cache in the working directory
mkdir "$GP_TEST_TMP/QuickProof"
cp "$GP_TEST_ROOT"/coq/QuickProof/*.v "$GP_TEST_TMP/QuickProof/"
cp "$GP_TEST_ROOT/tests/EnvEmpty.v" "$GP_TEST_TMP/EnvEmpty.v"
for module in Env Contract EnvBodies; do
  coqc -w -notation-incompatible-prefix -Q "$GP_TEST_TMP/QuickProof" QuickProof "$GP_TEST_TMP/QuickProof/$module.v"
done
coqc -w -notation-incompatible-prefix -Q "$GP_TEST_TMP/QuickProof" QuickProof "$GP_TEST_TMP/EnvEmpty.v"
cc -O0 -fno-delete-null-pointer-checks -fsanitize=address,undefined -I"$GP_TEST_ROOT/include" \
  -Dmain=harness_main -c "$GP_TEST_ROOT/tests/env_empty.c" -o "$GP_TEST_TMP/harness.o"
cc -O0 -fsanitize=address,undefined "$GP_TEST_TMP/harness.o" "$GP_TEST_ROOT/runtime/fuzz_driver.c" \
  -o "$GP_TEST_TMP/native"
"$GP_TEST_TMP/native" 10 1 0 10
cat > "$GP_TEST_TMP/quickproof.conf" <<'CONFIG'
INC=()
DEFS=()
UNITS=()
CONFIG
"$GP_TEST_ROOT/tools/interp.sh" "$GP_TEST_TMP/quickproof.conf" "$GP_TEST_ROOT/tests/env_empty.c" 1 10
