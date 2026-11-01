#!/usr/bin/env bash
# tests/qp/svcomp.sh: `tools/qp import-svcomp` on the tasks of tests/svcomp, offline.  Needs the toolchain in PATH
# (CompCert 3.15: clightgen, ccomp) and gcc with ASan/UBSan.  Writes only in a temporary directory.  Prints one
# ok/FAIL line per check; exit 0 iff all pass.
#
# tests/svcomp/c is a small tree in the layout of sv-benchmarks: task-definition files and C files written for
# these tests (c/quickproof/, PolyForm Noncommercial 1.0.0), two vendored tasks and the property files
# (tests/svcomp/SOURCES). It becomes a local git repository, the upstream of a project `sv` whose quickproof.conf
# lists no library unit.
#  1. the shim's declarations of the environment agree with quickproof.h and the C library's (one translation
#     unit with all three, for gcc and for clightgen);
#  2. every accepted task: the law, the copy of the task (normalised: glibc's assert expansion), the shim, the
#     libc, the managed blocks (units in quickproof.conf, BROKEN in project.conf), the provenance; the cone check
#     of three laws is clean (clightgen; also a task with glibc-style declarations that conflict with the system
#     headers);
#  3. determinism: importing again changes nothing; a second workspace, other environment: byte-identical;
#  4. refusals: each refused task (ILP32, no data model, nondet float or pointer, threads, setjmp/longjmp, inline
#     assembly, main with arguments, input functions, an unknown __VERIFIER function, a termination-only task,
#     two input files, a Juliet task) with its reason, and nothing written;
#  5. --verdicts: laws expected true show no counterexample (also where a failing assert() ends the execution;
#     a statement expression that the interpreter cannot compile gives no interpreter verdict, not a stop),
#     laws expected false show one (also with an empty reach_error), natively or under the interpreter; SVCOMP.md;
#  6. the standard gates on an imported law: qp fuzz (native) and qp interp (header-free interpreter driver).
set -uo pipefail
GP=$(cd "$(dirname "$0")/../.." && pwd)
QP=$GP/tools/qp
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
touch "$T/start"
fails=0
ok() { echo "ok   svcomp: $*"; }
bad() { echo "FAIL svcomp: $*"; fails=$((fails + 1)); }
G=(git -c user.name=qp-test -c user.email=qp-test@localhost -c init.defaultBranch=main)
unset QP_WORKSPACE QP_TEMPLATES QP_OPAM_SWITCH QP_FRAMEWORK_URL
export QP_SITE_CONF=/dev/null QP_CACHE=$T/cache QP_FRAMEWORK_DIR=$GP DEBUGINFOD_URLS= PYTHONDONTWRITEBYTECODE=1
run() {   # run LOG CMD...: the command's output in $T/LOG.log, its exit status in $rc
  local log=$1; shift
  if "$@" > "$T/$log.log" 2>&1; then rc=0; else rc=$?; fi
}
has() { grep -q -- "$2" "$T/$1.log"; }

# ---- 1. the shim's declarations against quickproof.h and the C library's
printf '#include <stdlib.h>\n#include <string.h>\n#include <assert.h>\n#include "quickproof.h"\n#include "svcomp_env.h"\n' > "$T/decl.c"
if gcc -fsyntax-only -I"$GP/include" -I"$GP/tools/svcomp" "$T/decl.c" > "$T/decl.log" 2>&1 &&
   clightgen -normalize -I"$GP/include" -I"$GP/tools/svcomp" "$T/decl.c" -o "$T/decl.v" >> "$T/decl.log" 2>&1; then
  ok "the shim's environment declarations agree with quickproof.h and the C library's (gcc, clightgen)"
else bad "shim declarations"; cat "$T/decl.log"; fi

# ---- the upstream and the project
cp -r "$GP/tests/svcomp" "$T/upstream"
(cd "$T/upstream" && "${G[@]}" init -q && "${G[@]}" add -A && "${G[@]}" commit -qm tasks)
UP=$(git -C "$T/upstream" rev-parse HEAD)
mkproject() {   # mkproject WORKSPACE: the project `sv` without imported laws
  mkdir -p "$1/projects/sv/harness"
  printf 'UPSTREAM=%s\nCOMMIT=%s\nFRAMEWORK=\nLOGICAL=Sv\nCODE="c/properties"\nPATCH=""\nBROKEN=""\n' "$T/upstream" "$UP" \
    > "$1/projects/sv/project.conf"
  printf 'LINK=per-law\nINC=()\nDEFS=()\nUNITS=()\n' > "$1/projects/sv/quickproof.conf"
}
mkproject "$T/ws"
P=$T/ws/projects/sv
Q=("$QP" --workspace "$T/ws")

# ---- 2. the accepted tasks (law, property chosen, task expected, law expected)
ACCEPT="nondet-values:unreach-call:true:true assume-exit:unreach-call:true:true reach-false:unreach-call:false:false
        heap-arbitrary:valid-memsafety:true:true heap-oob:valid-memsafety:false:false alloca-free:valid-memsafety:false:false
        leak:valid-memcleanup:false:false overflow:no-overflow:false:false own-functions:unreach-call:true:true
        glibc-like:unreach-call:true:true reach-error-empty:unreach-call:false:false assert-ends:unreach-call:true:true
        stmt-expr:unreach-call:true:true"
for e in $ACCEPT; do
  IFS=: read -r t prop tv lv <<< "$e"
  law=${t//-/_}
  case $t in glibc-like|heap-arbitrary|own-functions) check=() ;; *) check=(--no-check) ;; esac
  run "imp-$t" "${Q[@]}" import-svcomp sv "c/quickproof/$t.yml" "${check[@]}"
  if [ $rc = 0 ] && has "imp-$t" "^$law: property $prop, task expected $tv, law expected $lv$" &&
     [ -f "$P/harness/$law.c" ] && ls "$P/harness/svcomp/$law".[ci] > /dev/null 2>&1 &&
     grep -q "^ \*   command:        tools/qp import-svcomp sv c/quickproof/$t.yml --law $law --property $prop --malloc may-fail$" "$P/harness/$law.c" &&
     grep -q "\"harness/$law.c=src/harness/$law\"" "$P/quickproof.conf"; then
    if [ ${#check[@]} = 0 ] && ! has "imp-$t" 'ok: only the framework environment is external, no VST blocker in the cone'; then
      bad "import $t: cone check"; cat "$T/imp-$t.log"
    else ok "import $t: law $law, property $prop, expected $lv$([ ${#check[@]} = 0 ] && echo ', cone check clean')"; fi
  else bad "import $t"; cat "$T/imp-$t.log"; fi
done
# the managed blocks and the details of some laws
broken=$(bash -c 'cd "$1" && source ./project.conf > /dev/null && echo $BROKEN' _ "$P")
if [ "$broken" = "alloca_free heap_oob leak overflow reach_error_empty reach_false" ]; then ok "BROKEN: the laws expected false, from the managed block of project.conf"
else bad "BROKEN is '$broken'"; cat "$P/project.conf"; fi
if grep -q '((d.quot == n) ? (void) 0 : __assert_fail ("d.quot == n", "glibc-like.c", 31, __func__))' "$P/harness/svcomp/glibc_like.i" &&
   ! grep -q '__extension__ ({' "$P/harness/svcomp/glibc_like.i" &&
   grep -q '(2 glibc assert expansions rewritten without a statement expression; 2 __PRETTY_FUNCTION__ written __func__; 1 asm label of declarations kept for gcc only; a failing check at the start of reach_error)' "$P/harness/glibc_like.c" &&
   grep -q '__asm__ ("" "__isoc99_fscanf")' "$GP/tests/svcomp/c/quickproof/glibc-like.i" && grep -q ') QP_SVCOMP_ASM_LABEL ("" "__isoc99_fscanf");' "$P/harness/svcomp/glibc_like.i" &&
   [ "$(diff "$GP/tests/svcomp/c/quickproof/glibc-like.i" "$P/harness/svcomp/glibc_like.i" | grep -c '^[<>]')" = 6 ] &&
   grep -q '^void reach_error() { qp_svcomp_reach_error(); ((0) ? (void) 0 : __assert_fail ("0", "glibc-like.c", 17, __func__)); }$' "$P/harness/svcomp/glibc_like.i"; then
  ok "normalisation: only glibc's assert expansion, __PRETTY_FUNCTION__, asm labels and the start of reach_error are edited, and counted"
else bad "normalisation of glibc-like.i"; diff "$GP/tests/svcomp/c/quickproof/glibc-like.i" "$P/harness/svcomp/glibc_like.i"; fi
if grep -q '^ \*   task-defined:   __VERIFIER_assume, strlen$' "$P/harness/own_functions.c" &&
   grep -q '^#define QP_SVCOMP_OWN___VERIFIER_assume 1$' "$P/harness/own_functions.c" &&
   grep -q '^#define QP_SVCOMP_OWN_strlen 1$' "$P/harness/own_functions.c" &&
   grep -q '^#define QP_SVCOMP_LEAKS 1$' "$P/harness/leak.c" && grep -q 'qp_assert(qp_svcomp_live == 0);' "$P/harness/leak.c" &&
   grep -q '^ \*   verdicts:       valid-memsafety false (valid-deref)$' "$P/harness/heap_oob.c" &&
   grep -q '^ \*   law:            expected false (valid-memsafety (valid-free)), in BROKEN$' "$P/harness/alloca_free.c"; then
  ok "provenance: functions the task defines are left to it; valid-memcleanup counts blocks; verdicts and subproperties recorded"
else bad "provenance details"; head -40 "$P/harness/own_functions.c"; fi

mkproject "$T/wsu"
sed -i 's|^UNITS=()$|UNITS=("$GP/libc/malloc_unit.c=src/malloc")|' "$T/wsu/projects/sv/quickproof.conf"
run unitwarn "$QP" --workspace "$T/wsu" import-svcomp sv c/quickproof/assume-exit.yml --no-check
if [ $rc = 0 ] && has unitwarn 'warning: quickproof.conf lists library units (malloc_unit.c): the law needs none'; then
  ok "a library unit in quickproof.conf: warned (tools/interp.sh would put its system headers next to the task)"
else bad "library unit warning"; cat "$T/unitwarn.log"; fi

# ---- 3. determinism
run again "${Q[@]}" import-svcomp sv c/quickproof/heap-oob.yml --no-check
if [ $rc = 0 ] && [ "$(grep -c '^unchanged ' "$T/again.log")" = 4 ] && ! has again '^updated'; then
  ok "import again: every file unchanged"
else bad "import again"; cat "$T/again.log"; fi
mkproject "$T/ws2"
for e in $ACCEPT; do
  t=${e%%:*}
  (cd / && umask 077 && env TZ=Asia/Tokyo LANG=C PYTHONHASHSEED=4242 "$QP" --workspace "$T/ws2" import-svcomp sv "c/quickproof/$t.yml" --no-check) \
    > /dev/null 2>&1 || true
done
if diff -r "$P" "$T/ws2/projects/sv" > "$T/det.diff"; then
  ok "determinism: a second workspace, another time zone, locale, hash seed, umask and working directory: byte-identical"
else bad "determinism"; cat "$T/det.diff"; fi

# ---- 4. refusals
before=$(cd "$P" && find . -type f | sort | xargs sha256sum)
REFUSE=("refuse-ilp32|data model ILP32" "refuse-no-data-model|data model not given"
        "refuse-float|__VERIFIER_nondet_double: a floating-point value" "refuse-pointer|__VERIFIER_nondet_pointer: a pointer value"
        "refuse-thread|uses threads" "refuse-longjmp|uses setjmp/longjmp" "refuse-asm|uses inline assembly"
        "refuse-argv|main takes arguments" "refuse-input|reads input (fgets)" "refuse-unknown|__VERIFIER_nondet_foo: not an SV-COMP"
        "refuse-termination|no supported property (it has: termination"
        "refuse-two-files|2 input files")
for e in "${REFUSE[@]}"; do
  t=${e%%|*}; why=${e#*|}
  run "ref-$t" "${Q[@]}" import-svcomp sv "c/quickproof/$t.yml"
  if [ $rc != 0 ] && has "ref-$t" "$why"; then ok "refused $t: $why"; else bad "refusal of $t"; cat "$T/ref-$t.log"; fi
done
run ref-juliet "${Q[@]}" import-svcomp sv "c/Juliet_Test/CWE415_Double_Free---s01---CWE415_Double_Free__malloc_free_int_03_bad.yml"
if [ $rc != 0 ] && has ref-juliet 'main takes arguments (int argc, char \*\*argv)' && has ref-juliet 'reads input (sscanf, rand)'; then
  ok "refused a Juliet task: main takes arguments, it reads input"
else bad "refusal of the Juliet task"; cat "$T/ref-juliet.log"; fi
if [ "$before" = "$(cd "$P" && find . -type f | sort | xargs sha256sum)" ]; then ok "refusals write nothing"
else bad "a refusal wrote files"; fi
run vend "${Q[@]}" import-svcomp sv c/loop-invariants64/linear-inequality-inv-d.yml --no-check
if [ $rc = 0 ] && has vend '^linear_inequality_inv_d: property no-overflow, task expected true, law expected true$' &&
   grep -q '^ \*   verdicts:       no-overflow true; termination true; unreach-call true$' "$P/harness/linear_inequality_inv_d.c"; then
  ok "a vendored sv-benchmarks task (loop-invariants64, Apache-2.0): imported, its first supported property chosen"
else bad "vendored task"; cat "$T/vend.log"; fi

# ---- 5. --verdicts on a sample
run verd "${Q[@]}" import-svcomp sv --verdicts glibc_like heap_arbitrary assert_ends stmt_expr reach_false reach_error_empty heap_oob alloca_free leak overflow \
  -n 200 --timeout 5 --interp 1 --interp-timeout 10
v() { grep -A3 "^$1 (" "$T/verd.log" | grep -q "=> $2"; }
if [ $rc = 0 ] && v glibc_like 'agrees: no counterexample$' && v heap_arbitrary 'agrees: no counterexample$' &&
   v assert_ends 'agrees: no counterexample' && v stmt_expr 'agrees: no counterexample (no verdict from the interpreter)' && v reach_false 'agrees: counterexample found' && v reach_error_empty 'agrees: counterexample found' && v heap_oob 'agrees: counterexample found' &&
   v alloca_free 'agrees: counterexample found' && v leak 'agrees: counterexample found' && v overflow 'agrees: counterexample found' &&
   grep -A3 '^alloca_free (' "$T/verd.log" | grep -q 'interpreter: stop at seed 1: undefined behaviour: calling free' &&
   grep -q '^| `heap_oob` | valid-memsafety | false | false | ' "$P/SVCOMP.md"; then
  ok "--verdicts: the laws expected true show no counterexample, those expected false one each; SVCOMP.md"
else bad "--verdicts"; cat "$T/verd.log"; fi

# ---- 6. the standard gates
run gfuzz "${Q[@]}" fuzz sv glibc_like heap_arbitrary -n 50
run ginterp "${Q[@]}" interp sv glibc_like heap_arbitrary -n 2 --timeout 600
if has gfuzz '^glibc_like  *upstream  *ok (50 runs)' && has gfuzz '^heap_arbitrary  *upstream  *ok (50 runs)' &&
   has ginterp '^glibc_like  *interp  *ok (2 runs, no stop' && has ginterp '^heap_arbitrary  *interp  *ok (2 runs, no stop'; then
  ok "qp fuzz and qp interp on imported laws (the interpreter's header-free driver with a preprocessed task)"
else bad "qp fuzz / qp interp"; cat "$T/gfuzz.log" "$T/ginterp.log"; fi

new=$(find "$GP" -newer "$T/start" -type f -not -path '*/.git/*' -not -path "$GP/coq/*" | head)
if [ -z "$new" ]; then ok "nothing written in the framework checkout"; else bad "files written in the checkout: $new"; fi
[ "$fails" -eq 0 ]
