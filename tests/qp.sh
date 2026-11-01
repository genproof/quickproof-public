#!/usr/bin/env bash
# quickproof tests/qp.sh: the tests of tools/qp (called by tests/run.sh; also runs alone).  Needs the toolchain
# in PATH (Coq 8.20.1, VST 2.15, CompCert 3.15), gcc with ASan/UBSan and git; clang with libFuzzer for one
# check.  Writes only in temporary directories.  Exit 0 iff every test passes.
#
#  1. tests/qp/test_clight_audit.py: the Clight audit of a law's cone (blockers, review items, the cone);
#  2. tests/qp/test_vst_lint.py: qp's VST lint (bitfield composites in the Clight, switch fall-off);
#  3. tests/qp/test_templates.py: what `qp assemble --templates` writes (placeholders, paths, contract_decls);
#     tests/qp/test_helpers.py: the statement check of `qp rebuild` and the parallel jobs (QP_JOBS);
#  4. tests/qp/e2e.sh: every subcommand on a toy workspace, offline (new, tree, lint, audit, check, assemble,
#     export with verify, verify of a changed statement, rebuild, import-fuzz, determinism, replay, fidelity).
#  5. tests/qp/svcomp.sh: import-svcomp on the tasks of tests/svcomp (imports, refusals, determinism, --verdicts).
#  6. tests/qp/fuzz_engines.sh: import-fuzz --style afl|honggfuzz and --entry/--init/--cleanup/--define on toy
#     targets (imports, refusals, native runs, replay, determinism, fidelity).
#  7. tests/qp/cbmc.sh: import-cbmc on a toy upstream with vendored CBMC harness excerpts (the laws byte for byte,
#     the refusals, determinism, and end to end: cone, native gate, interpreter, a seeded fault).
#  8. tests/qp/libfuzzer.sh: qp fuzz --libfuzzer on a toy workspace (a false law crashes and replays, true laws
#     run clean, globals and heap are reset between inputs, --nondet env and direct).
set -uo pipefail
GP=$(cd "$(dirname "$0")/.." && pwd)
export PYTHONDONTWRITEBYTECODE=1
fails=0
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
for t in test_clight_audit test_vst_lint test_templates test_helpers; do
  if python3 "$GP/tests/qp/$t.py" > "$T/$t.log" 2>&1; then echo "ok   qp: tests/qp/$t.py"
  else echo "FAIL qp: tests/qp/$t.py"; tail -20 "$T/$t.log"; fails=$((fails + 1)); fi
done
v=$("$GP/tools/qp" --version)
if [[ $v =~ ^qp\ ([0-9]+\.[0-9]+\.[0-9]+)\  ]] && grep -q "^## \[${BASH_REMATCH[1]}\] - " "$GP/CHANGELOG.md"; then
  echo "ok   qp: --version ($v) names the latest release of CHANGELOG.md"
else echo "FAIL qp: --version: '$v' (no matching '## [VERSION] - DATE' in CHANGELOG.md)"; fails=$((fails + 1)); fi
bash "$GP/tests/qp/e2e.sh" || fails=$((fails + 1))
bash "$GP/tests/qp/svcomp.sh" || fails=$((fails + 1))
bash "$GP/tests/qp/fuzz_engines.sh" || fails=$((fails + 1))
bash "$GP/tests/qp/cbmc.sh" || fails=$((fails + 1))
bash "$GP/tests/qp/libfuzzer.sh" || fails=$((fails + 1))
[ "$fails" -eq 0 ]
