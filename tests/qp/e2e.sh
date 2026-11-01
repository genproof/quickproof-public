#!/usr/bin/env bash
# tests/qp/e2e.sh: tools/qp end to end on a toy workspace, offline.  Needs the toolchain in PATH (Coq 8.20.1,
# VST 2.15, CompCert 3.15), gcc with ASan/UBSan and git; clang with libFuzzer for `qp fidelity` (skipped
# without it).  Writes only in a temporary directory.  Prints one ok/FAIL line per check; exit 0 iff all pass.
#
# The upstream is a local git repository made of the framework's toy library (tests/perlaw/lib) and a fuzz
# target (tests/qp/upstream/counter_fuzzer.c), tagged v1.0; the framework is a git snapshot of this checkout
# (QP_FRAMEWORK_DIR), so that every commit the test pins exists locally.  Two projects:
#   toy    the two laws of tests/perlaw with an idiom patch (an include guard, which tools/interp.sh needs);
#          qp new, tree (the workspace found three ways; a pinned framework fetched from QP_FRAMEWORK_URL), lint,
#          audit, check, assemble, then the proof of tests/perlaw/proof with the laws stated in laws.v (the
#          contract commit holding only the programs in the contract files): export (verify: PASS), verify of a
#          proof that states a law on another program (FAIL; progress lines on stderr, the report on stdout),
#          verify of a commit that changed a harness (FAIL before the build; --keep-going: every check), rebuild of
#          the export;
#   cfuzz  the fuzz target imported as a law: import-fuzz (twice: unchanged), tools/fuzz/determinism.sh (also on
#          the project reached through a symlink, and with a symlinked harness/: it changes no file), replay
#          natively and under the interpreter, fidelity with a seeded fault;
# and a project whose harness has a goto: qp lint fails.
set -euo pipefail
GP=$(cd "$(dirname "$0")/../.." && pwd)
QP=$GP/tools/qp
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
touch "$T/start"
fails=0
ok() { echo "ok   qp: $*"; }
bad() { echo "FAIL qp: $*"; fails=$((fails + 1)); }
G=(git -c user.name=qp-test -c user.email=qp-test@localhost -c init.defaultBranch=main -c advice.detachedHead=false)
# no machine settings: the test's own cache, framework and workspaces
unset QP_WORKSPACE QP_FRAMEWORK_DIR QP_TEMPLATES QP_OPAM_SWITCH QP_FRAMEWORK_URL
export QP_SITE_CONF=/dev/null QP_CACHE=$T/cache QP_JOBS=2 DEBUGINFOD_URLS=
URL=https://github.com/genproof/quickproof-public.git
run() {   # run LOG CMD...: the command's output in $T/LOG.log, its exit status in $rc
  local log=$1; shift
  if "$@" > "$T/$log.log" 2>&1; then rc=0; else rc=$?; fi
}
has() { grep -q -- "$2" "$T/$1.log"; }

# the framework: a git snapshot of this checkout (sources only)
mkdir "$T/fw"
tar -C "$GP" --exclude=.git --exclude='*.vo' --exclude='*.vok' --exclude='*.vos' --exclude='*.glob' --exclude='.*.aux' \
    --exclude='Makefile.coq*' --exclude='.Makefile.coq.d' --exclude=.lia.cache --exclude=__pycache__ \
    --exclude=./tools/site.conf -cf - . | tar -C "$T/fw" -xf -
(cd "$T/fw" && "${G[@]}" init -q && "${G[@]}" add -A && "${G[@]}" commit -qm framework)
FWHEAD=$(git -C "$T/fw" rev-parse HEAD)
export QP_FRAMEWORK_DIR=$T/fw

# the upstream: v1.0, then one more commit
mkdir -p "$T/upstream/lib" "$T/upstream/fuzz"
cp "$GP"/tests/perlaw/lib/* "$T/upstream/lib/"
cp "$GP/tests/qp/upstream/counter_fuzzer.c" "$T/upstream/fuzz/"
(cd "$T/upstream" && "${G[@]}" init -q && "${G[@]}" add -A && "${G[@]}" commit -qm v1.0 && "${G[@]}" tag v1.0 &&
 echo later > NEWS && "${G[@]}" add NEWS && "${G[@]}" commit -qm later)
V1=$(git -C "$T/upstream" rev-parse 'v1.0^{commit}')

# ---- qp new
mkdir "$T/ws"
run new "$QP" --workspace "$T/ws" new toy "$T/upstream"
P=$T/ws/projects/toy
conf() { bash -c 'cd "$(dirname "$1")" && source "$1" > /dev/null && echo "$UPSTREAM|$COMMIT|$FRAMEWORK|$LOGICAL"' _ "$P/project.conf"; }
if [ $rc = 0 ] && [ "$(conf)" = "$T/upstream|$V1|$FWHEAD|Toy" ] && grep -q '^LINK=per-law$' "$P/quickproof.conf" &&
   grep -q '^#  "lib/counter.c=src/counter"$' "$P/quickproof.conf" && [ -f "$P/STATUS.md" ] && [ -d "$P/harness" ]; then
  ok "new: projects/toy pinned to the latest release tag v1.0 and the framework's HEAD; LINK=per-law; units listed"
else bad "new"; cat "$T/new.log"; conf; fi

# the toy project's files: the laws of tests/perlaw, the library units (qp adds the harness units), an idiom patch
sed -i -e 's|^CODE=""|CODE="lib"|' -e 's|^PATCH=""|PATCH="sh patch/guard.sh"|' "$P/project.conf"
cp "$GP"/tests/perlaw/harness/*.c "$P/harness/"
printf 'INC=(-Ilib)\nDEFS=()\nLINK=per-law\nUNITS=(\n  "lib/counter.c=src/counter"\n  "lib/log.c=src/log"\n  "lib/pair.c=src/pair"\n  "lib/big.c=src/big"\n)\n' \
  > "$P/quickproof.conf"
mkdir "$P/patch"
cat > "$P/patch/guard.sh" <<'EOF'
# The idiom patch of the toy: an include guard for lib/counter.h (tools/interp.sh runs every unit in one translation unit).
set -e
f=lib/counter.h
{ echo '#ifndef COUNTER_H'; echo '#define COUNTER_H'; cat "$f"; echo '#endif'; } > "$f.new"
mv "$f.new" "$f"
EOF

# ---- qp tree: the workspace from the working directory, from QP_WORKSPACE, from --workspace
run tree1 bash -c 'cd "$1/harness" && "$2" tree toy' _ "$P" "$QP"
tree=$(tail -1 "$T/tree1.log")
if [ $rc = 0 ] && [ "$(readlink "$tree/quickproof")" = "$T/fw" ] && grep -q '^#ifndef COUNTER_H' "$tree/lib/counter.h" &&
   grep -q '"harness/law_count.c=src/harness/law_count"' "$tree/quickproof.conf" && [ ! -e "$tree/NEWS" ]; then
  ok "tree: workspace found from the working directory; upstream at v1.0, patched, harness units added, quickproof/ linked"
else bad "tree (working directory)"; cat "$T/tree1.log"; fi
run tree2 bash -c 'cd / && QP_WORKSPACE="$1" "$2" tree toy --orig --out "$3"' _ "$T/ws" "$QP" "$T/orig"
if [ $rc = 0 ] && [ -f "$T/orig/lib/counter.c" ] && ! grep -q COUNTER_H "$T/orig/lib/counter.h"; then
  ok "tree --orig --out: workspace from QP_WORKSPACE; unpatched"
else bad "tree --orig"; cat "$T/tree2.log"; fi
run tree3 bash -c 'cd / && "$1" tree toy' _ "$QP"
if [ $rc != 0 ] && has tree3 'no workspace'; then ok "tree: no workspace found outside one: refused"
else bad "tree outside a workspace"; cat "$T/tree3.log"; fi
mkdir "$T/fresh"
run newfresh bash -c 'cd "$1" && "$2" new demo "$3"' _ "$T/fresh" "$QP" "$T/upstream"
if [ $rc = 0 ] && [ -f "$T/fresh/projects/demo/project.conf" ] && has newfresh 'the current directory becomes one'; then
  ok "new: without a workspace, the current directory becomes one (projects/demo created)"
else bad "new without a workspace"; cat "$T/newfresh.log"; fi
# a pinned framework that no local repository has: fetched from QP_FRAMEWORK_URL (here a local path)
run tree4 env -u QP_FRAMEWORK_DIR QP_FRAMEWORK_URL="$T/fw" "$QP" --workspace "$T/ws" tree toy --out "$T/pinned"
if [ $rc = 0 ] && [ "$(readlink "$T/pinned/quickproof")" = "$T/cache/framework/${FWHEAD:0:12}" ] &&
   [ -x "$T/pinned/quickproof/tools/clight.sh" ]; then
  ok "tree: the pinned framework commit fetched from QP_FRAMEWORK_URL into the cache"
else bad "tree with a fetched framework"; cat "$T/tree4.log"; fi

Q=("$QP" --workspace "$T/ws")
# ---- qp lint, audit
run lint "${Q[@]}" lint toy
if [ $rc = 0 ] && has lint '^clean$'; then ok "lint: clean"; else bad "lint"; cat "$T/lint.log"; fi
run audit "${Q[@]}" audit toy
if [ $rc = 0 ] && has audit 'law_count [0-9]* functions' && grep -A1 'BLOCKERS' "$T/audit.log" | grep -q 'none'; then
  ok "audit: the cones, no blocker"
else bad "audit"; cat "$T/audit.log"; fi
mkdir -p "$T/ws/projects/bad/harness"
cp "$P/project.conf" "$P/quickproof.conf" "$T/ws/projects/bad/"; cp -r "$P/patch" "$T/ws/projects/bad/"
cat > "$T/ws/projects/bad/harness/law_goto.c" <<'EOF'
/* Law law_goto: a law whose harness has a goto (VST has no rule for it). */
#include "quickproof.h"
#include "counter.h"

int main(void)
{
	struct counter c;
	c.n = 0;
	c.max = nondet_u32();
	if (c.max == 0)
		goto out;
	gp_assert(counter_inc(&c) == 1);
out:
	return 0;
}
EOF
run lintbad "${Q[@]}" lint bad
if [ $rc = 1 ] && has lintbad 'goto/label'; then ok "lint: a goto in a law's cone is a blocker (exit 1)"
else bad "lint of a goto"; cat "$T/lintbad.log"; fi

# ---- qp check (lint, native runs patched and unmodified, interpreter, mutants)
run check "${Q[@]}" check toy -n 100 --interp-runs 2 --mutant-runs 30 -k 5 --timeout 600
c=$P/CHECK.md
if [ $rc = 0 ] && grep -q '| `law_count` | patched | ok (100 runs) |' "$c" && grep -q '| `law_pair` | orig | ok (100 runs) |' "$c" &&
   grep -q '| `law_count` | ok (2 runs, no stop' "$c" && grep -q 'Killed by some harness: \*\*[1-5]/5\*\*' "$c"; then
  ok "check: CHECK.md with native runs (patched and unmodified), interpreter runs, mutants"
else bad "check"; tail -30 "$T/check.log"; fi

# ---- qp assemble
R=$T/repo
run assemble "${Q[@]}" assemble toy "$R"
if [ $rc = 0 ] && [ "$(git -C "$R" config -f .gitmodules submodule.quickproof.url)" = "$URL" ] &&
   [ "$(git -C "$R" ls-tree contract quickproof | awk '{print $3}')" = "$FWHEAD" ] &&
   grep -q '^Theorem law_count : harness_safe whole_prog\.$' "$R/src/contracts/law_count.v" &&
   grep -q 'Toy.contracts.law_pair.whole_prog' "$R/src/contracts/suite.v" && grep -q '^-R src Toy$' "$R/_CoqProject" &&
   [ -z "$(git -C "$R" status --porcelain)" ] && [ ! -e "$R/NEWS" ]; then
  ok "assemble: framework submodule at the pin (URL $URL), contracts, _CoqProject, one commit tagged contract"
else bad "assemble"; cat "$T/assemble.log"; fi

# the contract restated: the laws in laws.v, the contract files keep only their programs; then the proof
python3 - "$R" <<'EOF'
import sys
r = sys.argv[1]
for law in ('law_count', 'law_pair'):
    p = '%s/src/contracts/%s.v' % (r, law)
    s = open(p).read()
    s = s[:s.rindex('(* ---', 0, s.index('THE THEOREM'))].rstrip() + '\n'
    open(p, 'w').write(s)
open(r + '/src/contracts/laws.v', 'w').write(
    '(* The laws, stated on the programs of their contract files. *)\nRequire Import QuickProof.Contract.\n'
    'Require Toy.contracts.law_count Toy.contracts.law_pair.\n\n'
    'Theorem law_count : harness_safe Toy.contracts.law_count.whole_prog.\nProof.\nAdmitted.\n\n'
    'Theorem law_pair : harness_safe Toy.contracts.law_pair.whole_prog.\nProof.\nAdmitted.\n')
EOF
(cd "$R" && "${G[@]}" add -A && "${G[@]}" commit -qm 'contract: the laws in laws.v' && git tag -f contract > /dev/null)
mkdir "$R/src/proof"
cp "$GP"/tests/perlaw/proof/{Lib,LawCount,LawPair}.v "$R/src/proof/"
python3 - "$R" <<'EOF'
import sys
r = sys.argv[1]
p = r + '/src/contracts/laws.v'
s = open(p).read().replace('Toy.contracts.law_pair.\n\n', 'Toy.contracts.law_pair.\nRequire Toy.proof.LawCount Toy.proof.LawPair.\n\n', 1)
for law, m in (('law_count', 'LawCount'), ('law_pair', 'LawPair')):
    s = s.replace('Theorem %s : harness_safe Toy.contracts.%s.whole_prog.\nProof.\nAdmitted.' % (law, law),
                  'Theorem %s : harness_safe Toy.contracts.%s.whole_prog.\nProof. exact Toy.proof.%s.%s_proved. Qed.' % (law, law, m, law))
open(p, 'w').write(s)
p = r + '/src/contracts/suite.v'
s = open(p).read().replace('Require Toy.contracts.law_pair.\n', 'Require Toy.contracts.law_pair.\nRequire Toy.contracts.laws.\n')
s = s.replace('Proof.\nAdmitted.', 'Proof. split; [exact Toy.contracts.laws.law_count | exact Toy.contracts.laws.law_pair]. Qed.')
open(p, 'w').write(s)
EOF
(cd "$R" && "${G[@]}" add -A && "${G[@]}" commit -qm proof)
# a wrong proof on a branch: law_count stated on law_pair's program
(cd "$R" && "${G[@]}" checkout -q -b wrong &&
 sed -i -e 's/^Theorem law_count : harness_safe Toy.contracts.law_count.whole_prog\.$/Theorem law_count : harness_safe Toy.contracts.law_pair.whole_prog./' \
        -e 's/exact Toy.proof.LawCount.law_count_proved/exact Toy.proof.LawPair.law_pair_proved/' src/contracts/laws.v &&
 "${G[@]}" commit -qam wrong && "${G[@]}" checkout -q -)
# a contract whose program-only file is not the generator's (an extra definition before whole_prog), with its
# own contract tag: qp verify regenerates the program from the harness and refuses the committed one
(cd "$R" && "${G[@]}" checkout -q -b progedit contract &&
 sed -i 's/^Definition whole_prog\b/Definition qp_extra := 0.\nDefinition whole_prog/' src/contracts/law_count.v &&
 "${G[@]}" commit -qam 'contract with an edited program' && git tag contract-progedit && "${G[@]}" checkout -q -)
# a frozen file changed after the contract on another branch: a comment added to a harness
(cd "$R" && "${G[@]}" checkout -q -b tampered && echo '/* added after the contract */' >> harness/law_count.c &&
 "${G[@]}" commit -qam tampered && "${G[@]}" checkout -q -)

# ---- qp export (qp verify: PASS), then qp verify of the wrong proof and qp rebuild of the export, in parallel
run export "${Q[@]}" export toy "$R" --label demo
E=$P/proofs/demo
if [ $rc = 0 ] && has export 'Verdict: PASS' && has export 'no proof in them (src/contracts/law_count.v, src/contracts/law_pair.v, src/contracts/laws.v)' &&
   has export 'generated again: src/contracts/suite.v' &&
   has export 'elaborated statement and whole_prog of `law_count`: identical to the contract' &&
   grep -q '^Proved (Qed, checked by `qp verify`, see VERIFY.md): `law_count`, `law_pair`, `suite`\.$' "$E/PROOF.md" &&
   grep -q "^FRAMEWORK=$FWHEAD$" "$E/PROOF.md" && [ -f "$E/src/contracts/laws.v" ] && [ -f "$E/src/proof/Lib.v" ]; then
  ok "export: verify PASS (laws stated in laws.v, compared with the contract commit's laws.v and program-only contract files), proofs/demo written"
else bad "export"; tail -40 "$T/export.log"; fi
run progedit "$QP" verify "$R" --rev progedit --base contract-progedit
if [ "$rc" = 1 ] && has progedit 'whose program is not the one generated from their harness: \*\*src/contracts/law_count.v' &&
   has progedit 'Verdict: FAIL'; then
  ok "verify: a contract file whose program is not the generator's is refused, also when its law is stated in laws.v"
else bad "verify: an edited program-only contract file was accepted (rc $rc)"; tail -20 "$T/progedit.log"; fi
# the printed table counts each theorem's axioms, VERIFY.md lists them; the verification clones copy their objects
# (no hard links, which git refuses on overlayfs, as in a Docker container)
if has export '^| `suite` | PROVED | [0-9][0-9]*: standard' && ! has export '| Print Assumptions |' &&
   grep -q '^| theorem | result | Print Assumptions |$' "$E/VERIFY.md" && grep -q '^| `suite` | PROVED | .*classic' "$E/VERIFY.md" &&
   [ -d "$T/cache/verify" ] && [ -z "$(find "$T/cache/verify" -path '*/objects/*' -type f -links +1 | head -1)" ]; then
  ok "verify: axioms counted in the printed table, in full in VERIFY.md; clones without hard links"
else bad "verify: printed table, VERIFY.md or hard-linked clone"; grep -n '^|' "$T/export.log" | head; fi
STAMP='^\[[0-9]*:[0-9][0-9]\] '
# the report on stdout, the progress lines on stderr, kept apart for the checks below; `&& || ` captures the
# exit status without `set -e` killing the subshell at the (expected) non-zero verify
( "$QP" verify "$R" --rev wrong > "$T/wrong.log" 2> "$T/wrong.err" && echo 0 > "$T/wrong.rc" || echo $? > "$T/wrong.rc" ) &
( run rebuild "${Q[@]}" rebuild toy demo; echo $rc > "$T/rebuild.rc" ) &
wait
if [ "$(cat "$T/wrong.rc")" = 1 ] && has wrong '| `law_count` | STATEMENT CHANGED |' && has wrong 'Verdict: FAIL'; then
  ok "verify: a law proved on another program than its contract's: STATEMENT CHANGED, FAIL (exit 1)"
else bad "verify of a changed statement (rc $(cat "$T/wrong.rc"))"; tail -30 "$T/wrong.log"; fi
# progress lines: on stderr, one per stage, the builds counted in files; the report alone on stdout
if grep -q "${STAMP}qp verify: a fresh clone of $R at " "$T/wrong.err" &&
   grep -q "${STAMP}frozen files: [0-9]* files changed since the contract (\`contract\`), none of them frozen$" "$T/wrong.err" &&
   grep -q "${STAMP}Clight generated again: identical to the committed files$" "$T/wrong.err" &&
   grep -q "${STAMP}build: [1-9][0-9]*/[1-9][0-9]* files, [0-9]* s$" "$T/wrong.err" &&
   grep -q "${STAMP}build of the contract commit: [1-9][0-9]*/[1-9][0-9]* files, [0-9]* s$" "$T/wrong.err" &&
   grep -q "${STAMP}statements compared with the contract: DIFFERENT or missing$" "$T/wrong.err" &&
   grep -q "${STAMP}Admitted, admit, Axiom, Parameter, Conjecture in the sources of the proof: none$" "$T/wrong.err" &&
   ! grep -q "$STAMP" "$T/wrong.log" && grep -q '^# Verification of ' "$T/wrong.log"; then
  ok "verify: progress lines on stderr (each stage, both builds counted in files), the report alone on stdout"
else bad "verify: progress lines"; cat "$T/wrong.err"; fi
# a changed frozen file: FAIL at once, nothing built, VERIFY.md written.  Checked before --keep-going runs:
# both verify the same revision, so they share the verify cache directory (--keep-going then overwrites VERIFY.md).
run tampered "$QP" verify "$R" --rev tampered
VM=$T/cache/verify/repo-$(git -C "$R" rev-parse tampered | cut -c1-10)/VERIFY.md
if [ "$rc" = 1 ] && has tampered "${STAMP}frozen files changed since the contract: harness/law_count.c$" &&
   has tampered 'frozen files changed: harness/law_count.c$' && has tampered 'stopped before the build' &&
   has tampered 'Verdict: FAIL (exit 1)' && ! has tampered "${STAMP}build" && ! has tampered '| theorem |' &&
   grep -q 'stopped before the build' "$VM"; then
  ok "verify: a harness changed after the contract: FAIL (exit 1) before any build, the file named, VERIFY.md written"
else bad "verify: early exit on a changed frozen file (rc $rc)"; cat "$T/tampered.log"; fi
run tamperedk "$QP" verify "$R" --rev tampered --keep-going
if [ "$rc" = 1 ] && has tamperedk 'FAIL; going on: --keep-going' &&
   has tamperedk "${STAMP}build: [1-9][0-9]*/[1-9][0-9]* files" && has tamperedk '| `law_count` | PROVED |' &&
   has tamperedk 'Verdict: FAIL (exit 1)'; then
  ok "verify --keep-going: after a changed frozen file every check runs (the proof still builds), the verdict stays FAIL"
else bad "verify --keep-going (rc $rc)"; tail -30 "$T/tamperedk.log"; fi
if [ "$(cat "$T/rebuild.rc")" = 0 ] && [ "$(grep -cE '^(law_count|law_pair|suite) +PROVED$' "$T/rebuild.log")" = 3 ] &&
   has rebuild 'in the Coq sources (comments excluded): none'; then
  ok "rebuild: the export rebuilt from upstream, the workspace and the framework at its commit: 3 PROVED"
else bad "rebuild"; tail -30 "$T/rebuild.log"; fi

# ---- a law imported from a fuzz target: import-fuzz, determinism, replay, fidelity
F=$T/ws/projects/cfuzz
mkdir -p "$F/patch"
cp "$P/patch/guard.sh" "$F/patch/"
printf 'UPSTREAM=%s\nCOMMIT=%s\nFRAMEWORK=%s\nLOGICAL=CFuzz\nCODE="lib fuzz"\nPATCH="sh patch/guard.sh"\n' "$T/upstream" "$V1" "$FWHEAD" > "$F/project.conf"
printf 'INC=(-Ilib)\nDEFS=()\nLINK=per-law\nUNITS=(\n  "lib/counter.c=src/counter"\n  "lib/log.c=src/log"\n  "$GP/libc/libc.c=src/libc"\n  "$GP/libc/malloc_unit.c=src/malloc"\n)\n' \
  > "$F/quickproof.conf"
printf 'ORIG_SOURCES=(lib/counter.c lib/log.c)\nORIG_CFLAGS=(-Ilib)\n' > "$F/fuzz.conf"
run import "${Q[@]}" import-fuzz cfuzz fuzz/counter_fuzzer.c --max-len 64
if [ $rc = 0 ] && has import 'ok: only the framework environment is external, no VST blocker in the cone' &&
   grep -q '^ \*   importer:       tools/qp import-fuzz, version 2$' "$F/harness/counter.c" &&
   grep -q 'qp_assume(n <= 64);' "$F/harness/counter.c" && grep -q '#include "quickproof.h"' "$F/harness/fuzz/libfuzzer_env.h" &&
   grep -q '"harness/counter.c=src/harness/counter"' "$F/quickproof.conf"; then
  ok "import-fuzz: the law, the shim and its unit; the cone needs nothing outside the framework"
else bad "import-fuzz"; cat "$T/import.log"; fi
run import2 "${Q[@]}" import-fuzz cfuzz fuzz/counter_fuzzer.c --max-len 64 --no-check
if [ $rc = 0 ] && [ "$(grep -c '^unchanged ' "$T/import2.log")" = 2 ] && ! has import2 'updated'; then
  ok "import-fuzz again: every file unchanged"
else bad "import-fuzz again"; cat "$T/import2.log"; fi
run det "$GP/tools/fuzz/determinism.sh" --workspace "$T/ws" cfuzz
if [ $rc = 0 ] && has det 'run a = b: identical (3 files)' && has det 'run a = committed: identical (3 files)'; then
  ok "determinism.sh: two regenerations in other directories and environments are byte-identical to the project's"
else bad "determinism.sh"; cat "$T/det.log"; fi
# determinism.sh only reads the project, also when projects/NAME or its harness/ is a symlink, and compares the
# imported laws only (a hand-written law and header next to them are copied, not compared)
snapshot() { (cd "$1" && find -L . -type f -print0 | sort -z | xargs -0 sha256sum); }
for c in link harness; do
  W=$T/det-$c; mkdir -p "$W/ws/projects" "$W/real"
  cp -RL "$F" "$W/real/cfuzz"
  printf '// Law handwritten: a hand-written law next to the imported one (test fixture).\nint main(void) { return 0; }\n' \
    > "$W/real/cfuzz/harness/handwritten.c"
  printf '// a header of the hand-written law (test fixture)\n' > "$W/real/cfuzz/harness/handwritten.h"
  case $c in
    link)    ln -s "$W/real/cfuzz" "$W/ws/projects/cfuzz" ;;
    harness) mkdir "$W/real/h"; mv "$W/real/cfuzz/harness" "$W/real/h/harness"
             mv "$W/real/cfuzz" "$W/ws/projects/cfuzz"; ln -s "$W/real/h/harness" "$W/ws/projects/cfuzz/harness" ;;
  esac
  before=$(snapshot "$W/ws/projects/cfuzz")
  run "det-$c" "$GP/tools/fuzz/determinism.sh" --workspace "$W/ws" cfuzz
  if [ $rc = 0 ] && [ "$before" = "$(snapshot "$W/ws/projects/cfuzz")" ] && has "det-$c" 'run a = committed: identical (3 files)'; then
    ok "determinism.sh with a symlinked $([ $c = link ] && echo project || echo harness/): passes, the project's files unchanged"
  else bad "determinism.sh with a symlinked $c"; cat "$T/det-$c.log"; fi
done
C=$T/corpus/counter; mkdir -p "$C"
printf '' > "$C/empty"; printf '\000' > "$C/zero"; printf '\005abc' > "$C/five"; head -c 100 /dev/zero | tr '\0' a > "$C/long"
run replay "${Q[@]}" replay cfuzz counter "$C"
if [ $rc = 0 ] && has replay '^counter, native (patched): not covered 1, pass 3$'; then
  ok "replay: natively, 3 inputs pass, the one longer than --max-len is not covered"
else bad "replay"; cat "$T/replay.log"; fi
run replayi "${Q[@]}" replay cfuzz counter "$C/zero" "$C/five" --interp
if [ $rc = 0 ] && has replayi '^counter, interpreter: pass 2$'; then ok "replay --interp: 2 inputs pass under CompCert's interpreter"
else bad "replay --interp"; cat "$T/replayi.log"; fi
printf '#include <stdint.h>\n#include <stddef.h>\nint LLVMFuzzerTestOneInput(const uint8_t *d, size_t n) { return 0; }\n' > "$T/lf.c"
if clang -fsanitize=fuzzer "$T/lf.c" -o "$T/lf" > /dev/null 2>&1; then
  run fid "${Q[@]}" fidelity cfuzz --corpus "$T/corpus" --interp 2 --fault 'lib/counter.c|c->n = c->n + 1;|c->n = c->n + 2;'
  md=$F/FIDELITY.md
  if [ $rc = 0 ] && grep -q '^| `counter` | 4 | 1 | 0 | 0 | \*\*3/3\*\* |$' "$md" && grep -q '^| `counter` | 2 | \*\*2/2\*\* | 0 |$' "$md" &&
     grep -q '^| 0 | `counter` | 1 | 1 | \*\*3/3\*\* |$' "$md" && grep -A2 '^## Disagreements' "$md" | grep -q '^none$'; then
    ok "fidelity: the law agrees with the original target (natively, interpreter, under a seeded fault)"
  else bad "fidelity"; cat "$T/fid.log" "$md"; fi
else echo "skip qp: fidelity (no clang with libFuzzer)"; fi

# ---- verify guards (review B1, S2): qp verify refuses what is not a QuickProof proof on this framework
# a repository that is not a QuickProof proof at all (the reviewer's proof of concept): no framework, no
# quickproof.conf, its own harness_safe := True, proved by `exact I`
mkdir -p "$T/fake/src/contracts" && (cd "$T/fake" && "${G[@]}" init -q)
printf -- '-R src Fake\nsrc\n' > "$T/fake/_CoqProject"
cat > "$T/fake/src/contracts/law.v" <<'EOF'
Definition whole_prog : nat := 0.
Definition harness_safe (p : nat) : Prop := True.
Theorem law : harness_safe whole_prog.
Proof. Admitted.
EOF
(cd "$T/fake" && "${G[@]}" add -A && "${G[@]}" commit -qm contract && git tag contract &&
 sed -i 's/^Proof\. Admitted\./Proof. exact I. Qed./' src/contracts/law.v && "${G[@]}" commit -qam proof)
run fake "$QP" verify "$T/fake"
if [ "$rc" = 1 ] && has fake 'not a QuickProof proof repository' && has fake 'no quickproof/ framework submodule' &&
   has fake 'Verdict: FAIL' && ! has fake '| `law` | PROVED'; then
  ok "verify: a repository that is not a QuickProof proof (no framework, no quickproof.conf, its own harness_safe) is refused"
else bad "verify: fake-proof PoC not refused (rc $rc)"; cat "$T/fake.log"; fi

# no contract to compare against: UNVERIFIED, never PASS, even though the theorem is proved
run nobase "$QP" verify "$R" --base no-such-tag
if [ "$rc" = 1 ] && has nobase 'UNVERIFIED: no contract commit' && has nobase 'Verdict: FAIL' && ! has nobase 'Verdict: PASS'; then
  ok "verify: no contract (no tag, no --base): UNVERIFIED and FAIL, never PASS"
else bad "verify: no base still passed (rc $rc)"; tail -20 "$T/nobase.log"; fi

# a forked framework (a weakened Env.v in the pinned submodule): the trusted files are no longer this verifier's
FWORIG=$(git -C "$R/quickproof" rev-parse HEAD)
(cd "$T/fw" && echo '(* forked: a weakened Env *)' >> coq/QuickProof/Env.v &&
 "${G[@]}" add -A && "${G[@]}" commit -qm 'fork Env.v')
FWFORK=$(git -C "$T/fw" rev-parse HEAD)
(cd "$R" && "${G[@]}" checkout -q -b forked && git -C quickproof fetch -q "$T/fw" &&
 git -C quickproof checkout -q "$FWFORK" && "${G[@]}" add quickproof && "${G[@]}" commit -qm 'framework fork' &&
 "${G[@]}" checkout -q - && git -C quickproof checkout -q "$FWORIG")   # the submodule's worktree back to the pin
run fork "$QP" verify "$R" --rev forked
if [ "$rc" = 1 ] && has fork 'quickproof/ is not the framework of this verifier' && has fork 'changed coq/QuickProof/Env.v' &&
   has fork 'Verdict: FAIL'; then
  ok "verify: a pinned framework whose trusted files (Env.v) differ from this verifier's is refused"
else bad "verify: forked framework not refused (rc $rc)"; tail -20 "$T/fork.log"; fi
(cd "$T/fw" && "${G[@]}" reset -q --hard HEAD~1)   # undo the fork for any later test

# code-loading options in _CoqProject and unsafe vernac in a source are refused (S2)
(cd "$R" && "${G[@]}" checkout -q -b plugin &&
 printf -- '-I src\n' >> _CoqProject && printf 'DECLARE PLUGIN "evil"\n' > src/evil.mlg &&
 printf 'Declare ML Module "evil".\n' > src/proof/Evil.v &&
 "${G[@]}" add -A && "${G[@]}" commit -qm plugin && "${G[@]}" checkout -q -)
run plugin "$QP" verify "$R" --rev plugin
if [ "$rc" = 1 ] && has plugin 'refused' && has plugin 'OCaml plugin' && has plugin 'Verdict: FAIL' && ! has plugin '| theorem |'; then
  ok "verify: _CoqProject -I, a .mlg plugin file and Declare ML Module are refused before the build"
else bad "verify: plugin not refused (rc $rc)"; tail -25 "$T/plugin.log"; fi
(cd "$R" && "${G[@]}" checkout -q -b unsafe &&
 printf 'Unset Universe Checking.\n' > src/proof/Unsafe.v && "${G[@]}" add -A && "${G[@]}" commit -qm unsafe &&
 "${G[@]}" checkout -q -)
run unsafe "$QP" verify "$R" --rev unsafe
if [ "$rc" = 1 ] && has unsafe 'refused' && has unsafe 'Unset Universe Checking' && has unsafe 'Verdict: FAIL'; then
  ok "verify: Unset Universe Checking in a proof source is refused"
else bad "verify: unsafe vernac not refused (rc $rc)"; tail -20 "$T/unsafe.log"; fi

# a theorem stated on a repository-defined harness_safe (not QuickProof.Contract.harness_safe) is not accepted
(cd "$R" && "${G[@]}" checkout -q -b localhs &&
 printf 'Definition whole_prog := tt.\nDefinition harness_safe (p : unit) : Prop := True.\nTheorem evil_law : harness_safe whole_prog.\nProof. exact I. Qed.\n' > src/contracts/evil.v &&
 "${G[@]}" add -A && "${G[@]}" commit -qm localhs && "${G[@]}" checkout -q -)
run localhs "$QP" verify "$R" --rev localhs
if [ "$rc" = 1 ] && has localhs 'NOT QuickProof.Contract.harness_safe' && has localhs 'Verdict: FAIL'; then
  ok "verify: a theorem stated on a repository-defined harness_safe is not accepted (NOT QuickProof.Contract.harness_safe)"
else bad "verify: repository-defined harness_safe accepted (rc $rc)"; tail -25 "$T/localhs.log"; fi

# a quickproof.conf that runs a command (review round 2, B1): it could rewrite the framework's Contract.v after the
# framework was compared with this verifier's.  Refused before anything sources it, so nothing is built.
(cd "$R" && "${G[@]}" checkout -q -b evilconf contract &&
 printf '%s\n' 'f=quickproof/coq/QuickProof/Contract.v; [ -f "$f" ] && echo "(* changed *)" >> "$f" || true' >> quickproof.conf &&
 "${G[@]}" commit -qam 'contract with a command in quickproof.conf' && git tag contract-evilconf && "${G[@]}" checkout -q -)
run evilconf "$QP" verify "$R" --rev evilconf --base contract-evilconf
if [ "$rc" = 1 ] && has evilconf 'refused (runs commands)' && has evilconf 'quickproof.conf is not data' &&
   has evilconf 'Verdict: FAIL' && ! has evilconf '| theorem |'; then
  ok "verify: a quickproof.conf that runs a command is refused before it is sourced"
else bad "verify: a quickproof.conf with a command was not refused (rc $rc)"; tail -20 "$T/evilconf.log"; fi
for c in 'X=$(id)' 'PATH=/tmp:$PATH' 'DEFS=(-DA=1); id' 'INC=(-I. "`id`")'; do
  printf '%s\n' "$c" > "$T/c.conf"
  if python3 "$GP/tools/conf.py" "$T/c.conf" 2> /dev/null; then bad "conf.py accepted: $c"; fi
done
if python3 "$GP/tools/conf.py" "$GP"/examples/*/quickproof.conf; then
  ok "conf.py: commands, substitutions and reserved names refused; the examples' confs accepted"
else bad "conf.py refused an example's quickproof.conf"; fi

# a lemma left Admitted in the proof's sources fails verify, even when no theorem uses it
(cd "$R" && "${G[@]}" checkout -q -b deadadmit &&
 printf 'Lemma qp_unused : True.\nAdmitted.\n' > src/proof/Dead.v && "${G[@]}" add -A && "${G[@]}" commit -qm dead &&
 "${G[@]}" checkout -q -)
run deadadmit "$QP" verify "$R" --rev deadadmit
if [ "$rc" = 1 ] && has deadadmit 'src/proof/Dead.v:2 (Admitted)' && has deadadmit '| `suite` | PROVED' &&
   has deadadmit 'Verdict: FAIL'; then
  ok "verify: an Admitted lemma in the proof's sources is a FAIL, even when every theorem is proved"
else bad "verify: a dead Admitted passed (rc $rc)"; tail -20 "$T/deadadmit.log"; fi

# --coqchk re-checks the theorems' modules on a good proof
run coqchk "$QP" verify "$R" --coqchk
if [ "$rc" = 0 ] && has coqchk '^- coqchk: OK' && has coqchk 'Verdict: PASS'; then
  ok "verify --coqchk: the kernel re-checks the theorems' modules; PASS"
else bad "verify --coqchk (rc $rc)"; tail -20 "$T/coqchk.log"; fi


# ---- qp mutants: a law whose runs always time out (a loaded machine, or a non-terminating law) still gets a
# usable baseline, instead of being dropped as "fails on every seed" (a timeout is not a finding of the law)
MT=$T/ws/projects/mt
mkdir -p "$MT/harness"; cp "$P/project.conf" "$P/quickproof.conf" "$MT/"; cp -r "$P/patch" "$MT/"
cat > "$MT/harness/law_slow.c" <<'EOF'
/* Law law_slow: never terminates, so every native run hits the per-seed timeout (test fixture for qp mutants). */
#include "quickproof.h"
#include "counter.h"
int main(void)
{
	unsigned x = nondet_u32();
	gp_assume(x < 4000000000u);
	volatile unsigned long i = 0;
	while (1)
		i++;
	gp_assert(1);
}
EOF
run mt "${Q[@]}" mutants mt law_slow -n 2 -k 2
if [ $rc = 0 ] && ! has mt 'Not counted' && ! has mt 'no usable baseline' && has mt 'Killed by some harness'; then
  ok "mutants: a law whose baseline always times out keeps a usable baseline (timeouts are not findings), not 'not counted'"
else bad "mutants: timing-out baseline dropped"; cat "$T/mt.log"; fi

# ---- nothing written outside the temporary directory (but the Coq library's build products)
new=$(find "$GP" -newer "$T/start" -type f -not -path '*/.git/*' -not -path "$GP/coq/*" | head)
if [ -z "$new" ]; then ok "nothing written in the framework checkout"; else bad "files written in the checkout: $new"; fi

[ "$fails" -eq 0 ]
