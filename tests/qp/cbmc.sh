#!/usr/bin/env bash
# tests/qp/cbmc.sh: tools/qp import-cbmc on a toy upstream, offline (called by tests/qp.sh; also runs alone).
# Needs clang (the importer reads the harness code through clang's AST), gcc with ASan/UBSan and git; the end-to-end
# part also needs the toolchain in PATH (clightgen, ccomp).  Writes only in a temporary directory.  Prints one
# ok/FAIL line per check; exit 0 iff all pass.  QP_UPDATE_GOLDEN=1 rewrites tests/cbmc/expected instead of
# comparing (review the diff before committing it).
#
# The upstream is tests/cbmc/upstream, committed with a fixed date so that its commit is the same in every run:
#   toy/   a toy library and toy proofs in the cbmc-starter-kit layout, one per case of the design's test plan;
#   mqtt/  coreMQTT's MQTT_MatchTopic proof (vendored, MIT) over stand-in library code;
#   aws/   aws-c-common's aws_add_size_checked proof (vendored, Apache-2.0) over stand-in library code.
# Checks: the imported laws byte for byte (tests/cbmc/expected, the upstream path normalised), the importer's block
# of quickproof.conf, the refusals with their reasons (and nothing written), a second import that changes nothing,
# a conflict between two laws' library configurations, tools/fuzz/determinism.sh, and end to end: the cone, the
# native gate and the interpreter on MQTT_MatchTopic with the widened bound, a seeded fault caught natively and
# by the interpreter, and qp fuzz of a law whose harness code refers to a function defined nowhere.
set -uo pipefail
GP=$(cd "$(dirname "$0")/../.." && pwd)
QP=$GP/tools/qp
EXP=$GP/tests/cbmc/expected
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
touch "$T/start"
fails=0
ok() { echo "ok   qp cbmc: $*"; }
bad() { echo "FAIL qp cbmc: $*"; fails=$((fails + 1)); }
run() {   # run LOG CMD...: the command's output in $T/LOG.log, its exit status in $rc
  local log=$1; shift
  if "$@" > "$T/$log.log" 2>&1; then rc=0; else rc=$?; fi
}
has() { grep -q -- "$2" "$T/$1.log"; }
unset QP_WORKSPACE QP_FRAMEWORK_DIR QP_TEMPLATES QP_FRAMEWORK_URL QP_OPAM_SWITCH
export QP_SITE_CONF=/dev/null QP_CACHE=$T/cache QP_JOBS=2 DEBUGINFOD_URLS= PYTHONDONTWRITEBYTECODE=1
G=(git -c user.name=qp-test -c user.email=qp-test@localhost -c init.defaultBranch=main)

# the unit tests of the Makefile reader and the type resolver
if python3 "$GP/tests/qp/test_cbmc_make.py" > "$T/unit.log" 2>&1; then ok "tests/qp/test_cbmc_make.py ($(grep -c '^ok' "$T/unit.log") checks)"
else bad "tests/qp/test_cbmc_make.py"; grep FAIL "$T/unit.log"; fi

# the upstream: a fixed commit
mkdir "$T/upstream"; cp -R "$GP/tests/cbmc/upstream/." "$T/upstream/"
(cd "$T/upstream" && "${G[@]}" init -q && "${G[@]}" add -A &&
 GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z "${G[@]}" commit -qm upstream)
H=$(git -C "$T/upstream" rev-parse HEAD)
WS=$T/ws
Q=("$QP" --workspace "$WS")
project() {   # project NAME CODE [PATCH]: FRAMEWORK empty = this checkout
  mkdir -p "$WS/projects/$1/harness"
  printf 'UPSTREAM=%s\nCOMMIT=%s\nFRAMEWORK=\nLOGICAL=%s\nCODE="%s"\nPATCH="%s"\n' "$T/upstream" "$H" "T$1" "$2" "${3:-}" \
    > "$WS/projects/$1/project.conf"
  printf 'LINK=per-law\nINC=()\nDEFS=()\nUNITS=(\n  "$GP/libc/libc.c=src/libc"\n  "$GP/libc/malloc_unit.c=src/malloc"\n)\n' \
    > "$WS/projects/$1/quickproof.conf"
}
project toy toy; project mqtt mqtt; project aws aws
printf 'IMPORT_OPTS=(--undef CBMC)\n' > "$WS/projects/aws/cbmc.conf"

# ---- accepted imports (no check): every case of the design's test plan that translates
imports=(
  "toy havoc_types"
  "toy allocs"
  "toy allocs --law allocs_nf --malloc never-fails"
  "toy nondet_fns"
  "toy uninterp"
  "toy bounds --set MAX_LEN=100000"
  "toy libc_model"
  "toy approx --approx-mem-predicates"
  "toy entry_params"
  "toy undef_cbmc --undef CBMC"
  "mqtt MQTT_MatchTopic"
  "aws aws_add_size_checked"
)
for spec in "${imports[@]}"; do
  set -- $spec; p=$1; pr=$2; shift 2
  case $p in toy) d=toy/cbmc/proofs/$pr;; mqtt) d=mqtt/test/cbmc/proofs/$pr;; aws) d=aws/verification/cbmc/proofs/$pr;; esac
  run "imp_${p}_$pr" "${Q[@]}" import-cbmc "$p" "$d" --no-check "$@"
  if [ $rc = 0 ] && has "imp_${p}_$pr" '^wrote projects/'"$p"'/harness/'; then :; else bad "import $spec"; cat "$T/imp_${p}_$pr.log"; fi
done
ok "import-cbmc: ${#imports[@]} imports of the toy upstream written (exit 0)"

# the laws byte for byte (the upstream path, a temporary directory, normalised)
for p in toy mqtt aws; do
  mkdir -p "$T/got/$p"
  (cd "$WS/projects/$p" && find harness env quickproof.conf -type f | LC_ALL=C sort | while read -r f; do
     mkdir -p "$T/got/$p/$(dirname "$f")"; sed "s|$T/upstream|@UPSTREAM@|g" "$f" > "$T/got/$p/$f"; done)
done
if [ "${QP_UPDATE_GOLDEN:-}" = 1 ]; then
  rm -rf "$EXP"; mkdir -p "$EXP"; cp -R "$T/got/." "$EXP/"; echo "updated $EXP"
elif diff -r "$EXP" "$T/got" > "$T/golden.diff"; then
  ok "the imported laws, rewritten harness code, shim, env files and quickproof.conf equal tests/cbmc/expected ($(find "$EXP" -type f | wc -l) files)"
else bad "output differs from tests/cbmc/expected"; head -60 "$T/golden.diff"; fi

# spot checks of what the goldens hold
L=$WS/projects/toy/harness
c=$L/cbmc/havoc_types/havoc_types_harness.c
if grep -q 'bool b; QP_CBMC_HAVOC_BOOL(b);' "$c" && grep -q 'char c; QP_CBMC_HAVOC_SCHAR(c);' "$c" &&
   grep -q 'uint16_t x, y; QP_CBMC_HAVOC(x); QP_CBMC_HAVOC(y);' "$c" && grep -q 'int nested; QP_CBMC_HAVOC(nested);' "$c" &&
   grep -q 'anon_t a; qp_cbmc_havoc_typedef_anon_t' "$c" && grep -q '^#line 1 "toy/cbmc/proofs/havoc_types/havoc_types_harness.c"$' "$c" &&
   grep -q 'QP_CBMC_HAVOC_BYTES(qp_p->u);' "$L/havoc_types.c" && grep -q 'qp_p->bits = qp_t;' "$L/havoc_types.c"; then
  ok "havoc: _Bool 0/1, char by conversion, declaration lists, nested blocks, typedef'd anonymous structs, unions as bytes, bit-fields"
else bad "havoc spot checks"; fi
c=$L/cbmc/allocs/allocs_harness.c
if grep -q 'struct toy_buf \*b = qp_cbmc_malloc_struct_toy_buf();' "$c" && grep -q 'bool \*flag = qp_cbmc_malloc_scalar_bool();' "$c" &&
   grep -q 'malloc(sizeof(struct toy_buf) \* 2)' "$c" && grep -q 'calloc(1, sizeof(struct toy_buf))' "$c" &&
   grep -q 'viaexpr = qp_cbmc_malloc_struct_toy_buf();' "$c" && grep -q '^#define QP_CBMC_MALLOC QP_CBMC_MALLOC_NEVER_FAILS$' "$L/allocs_nf.c"; then
  ok "allocation: typed malloc(sizeof(T)) and sizeof(*p), bytes for arrays, calloc unchanged, --malloc never-fails"
else bad "allocation spot checks"; fi
if grep -q '^int nondet_uchar(void);$' "$L/nondet_fns.c" && grep -q '^void \*nondet_voidp(void)$' "$L/nondet_fns.c" &&
   grep -q '^int nondet_in_range(int qp_a0, int qp_a1)$' "$L/nondet_fns.c" &&
   grep -q '^#define __CPROVER_uninterpreted_hash(...) qp_cbmc_uninterpreted_hash()$' "$L/uninterp.c" &&
   grep -q '^uint64_t qp_cbmc_uninterpreted_hash(void);$' "$L/uninterp.c" && grep -q 'uninterpreted function hash returns' "$L/uninterp.c"; then
  ok "nondet functions with and without a prototype, uninterpreted functions with inconsistent declarations"
else bad "nondet/uninterpreted spot checks"; fi
if grep -q '^#define MAX_LEN 100000$' "$L/bounds.c" && grep -q 'MAX_LEN=100000 (widened with --set; upstream' "$L/bounds.c" &&
   grep -q 'dropped:        UNWINDSET toy_count.0:100000' "$L/bounds.c" && grep -q '^#define TOY_HARNESS_ONLY (1 + 1)$' "$L/bounds.c" &&
   grep -q "^DEFS+=(.*-DTOY_CONFIG=1)" "$WS/projects/toy/quickproof.conf" && ! grep -q 'NEVER' "$L/bounds.c"; then
  ok "bounds widened with --set and named in the claim, UNWINDSET dropped, library defines project-wide, harness defines law-local"
else bad "bounds spot checks"; fi
if grep -q 'replaced:       toy/cbmc/stubs/memcpy_model.c (a CBMC model of memcpy)' "$L/libc_model.c" &&
   [ ! -e "$L/cbmc/libc_model/memcpy_model.c" ] && grep -q '^#define QP_CBMC_APPROX_MEM_PREDICATES 1$' "$L/approx.c" &&
   grep -q 'in 1 assertion(s) the' "$L/approx.c" && grep -q 'in 1 assumption(s) the assumption is dropped' "$L/approx.c" &&
   grep -q 'without CBMC (--undef): the checks the library makes only under CBMC' "$L/undef_cbmc.c" && grep -q 'harness(qp_arg0, qp_arg1, qp_arg2);' "$L/entry_params.c" &&
   grep -q '#include "../../../toy/cbmc/proofs/entry_params/local.h"' "$L/cbmc/entry_params/entry_params_harness.c"; then
  ok "CBMC's libc models replaced, --approx-mem-predicates in the claim, --undef, entry parameters, headers next to the harness"
else bad "libc/approx/undef/entry spot checks"; fi

# ---- refusals: exit 2, the reason, nothing written
refusals=(
  "remove_lib|REMOVE_FUNCTION_BODY toy_replaceable: the library defines it"
  "approx|uses __CPROVER_w_ok (toy/cbmc/stubs/fill_stub.c): pointer validity has no plain-C counterpart"
  "approx_cond --approx-mem-predicates|__CPROVER_r_ok outside an assertion or assumption"
  "havoc_object|uses __CPROVER_havoc_object"
  "file_local|uses __CPROVER_file_local_toy_c_toy_hidden"
  "quantifier|uses __CPROVER_forall"
  "pointer_object|uses __CPROVER_POINTER_OBJECT"
  "contracts|CHECK_FUNCTION_CONTRACTS is set"
  "float_local|an arbitrary floating-point value (double)"
  "nondet_static|--nondet-static (NONDET_STATIC)"
  "no_entry|the entry function proof_main is not defined in the harness code"
  "undef_cbmc|through a macro of the library's toy/src/toy.h"
  "compile_error|rejected by a C compiler (clang), although CBMC may accept it"
)
n=0
for r in "${refusals[@]}"; do
  set -- ${r%%|*}; pr=$1; shift; why=${r#*|}
  run "ref_$pr" "${Q[@]}" import-cbmc toy "toy/cbmc/proofs/$pr" --no-check --law "ref_$pr" "$@"
  if [ $rc = 2 ] && grep -qF -- "refused: " "$T/ref_$pr.log" && grep -qF -- "$why" "$T/ref_$pr.log" &&
     [ ! -e "$WS/projects/toy/harness/ref_$pr.c" ] && [ ! -e "$WS/projects/toy/harness/cbmc/ref_$pr" ]; then n=$((n + 1))
  else bad "refusal of $pr: expected \"$why\""; cat "$T/ref_$pr.log"; fi
done
[ "$n" = "${#refusals[@]}" ] && ok "refused with the reason and nothing written: $n constructs of the design's section 4"
# cbmc.conf's IMPORT_OPTS apply (the aws law above has --undef CBMC from there); without them the library's
# CBMC-only header is refused and named
mv "$WS/projects/aws/cbmc.conf" "$T/cbmc.conf"
run ref_aws "${Q[@]}" import-cbmc aws aws/verification/cbmc/proofs/aws_add_size_checked --no-check --law ref_aws
mv "$T/cbmc.conf" "$WS/projects/aws/cbmc.conf"
if [ $rc = 2 ] && has ref_aws 'uses __CPROVER_overflow_plus' && has ref_aws 'aws/include/aws/common/math.h' &&
   grep -q -- 'command: .* --undef CBMC$' "$WS/projects/aws/harness/aws_add_size_checked.c"; then
  ok "cbmc.conf IMPORT_OPTS apply; without --undef CBMC the library's CBMC-only header is refused and named"
else bad "cbmc.conf / CBMC-only library header"; cat "$T/ref_aws.log"; fi

# ---- importing again changes nothing; a conflict between two laws' library configurations
run again "${Q[@]}" import-cbmc toy toy/cbmc/proofs/bounds --no-check --set MAX_LEN=100000
if [ $rc = 0 ] && ! has again '^wrote' && ! has again '^updated' && has again '^unchanged projects/toy/harness/bounds.c'; then
  ok "import again: every file unchanged"
else bad "import again"; cat "$T/again.log"; fi
run conflict "${Q[@]}" import-cbmc toy toy/cbmc/proofs/bounds --no-check --law bounds2 --set TOY_CONFIG=2
if [ $rc = 2 ] && has conflict 'the project-wide define -DTOY_CONFIG=2 of law bounds2 conflicts with -DTOY_CONFIG=1' &&
   [ ! -e "$WS/projects/toy/harness/bounds2.c" ]; then
  ok "a library define that differs between two laws of a project: refused"
else bad "conflicting library defines"; cat "$T/conflict.log"; fi

# ---- determinism: every law of the toy project regenerated in other directories and environments
run det "$GP/tools/fuzz/determinism.sh" --workspace "$WS" toy
if [ $rc = 0 ] && has det 'run a = b: identical' && has det 'run a = committed: identical'; then
  ok "determinism.sh: the CBMC laws regenerated twice elsewhere are byte-identical ($(grep -o 'identical ([0-9]* files)' "$T/det.log" | head -1))"
else bad "determinism.sh"; cat "$T/det.log"; fi

# ---- end to end: the cone, the native gate and the interpreter (the toolchain is needed)
if command -v clightgen > /dev/null && command -v ccomp > /dev/null; then
  run e2e "${Q[@]}" import-cbmc mqtt mqtt/test/cbmc/proofs/MQTT_MatchTopic --set MAX_TOPIC_NAME_FILTER_LENGTH=65536 \
    --runs 300 --interp 2
  if [ $rc = 0 ] && has e2e '^cone: [0-9]* functions; no VST blocker' && has e2e '^clean, non-vacuous (300 runs' &&
     has e2e '^== interpreter (2 seeds that pass every assumption natively' && has e2e '^no stop (2 seeds'; then
    ok "MQTT_MatchTopic (vendored) with every topic length: cone without blocker, native gate clean and non-vacuous, interpreter without stop"
  else bad "end to end on MQTT_MatchTopic"; cat "$T/e2e.log"; fi
  # a seeded fault (an off-by-one index) in the library, through the project's PATCH
  project mqttfault mqtt "sh patch/fault.sh"
  mkdir "$WS/projects/mqttfault/patch"
  cat > "$WS/projects/mqttfault/patch/fault.sh" <<'EOF'
sed -i 's/if (pTopicName\[0\] == /if (pTopicName[topicNameLength] == /' mqtt/source/core_mqtt.c
EOF
  run fault "${Q[@]}" import-cbmc mqttfault mqtt/test/cbmc/proofs/MQTT_MatchTopic --runs 300 --interp 3
  if [ $rc = 0 ] && has fault '^FINDING: ' && has fault 'heap-buffer-overflow' && has fault '^== interpreter on the failing seed' &&
     has fault '^STOP at seed [0-9]*: in function MQTT_MatchTopic'; then
    ok "a seeded off-by-one in the library: caught by the native gate (ASan), and the failing seed stops the interpreter"
  else bad "seeded fault"; cat "$T/fault.log"; fi
else echo "skip qp cbmc: end to end (no clightgen/ccomp in PATH)"; fi

# ---- qp fuzz (and so qp check and qp mutants) links an imported law whose harness code refers to a function defined
#      nowhere as the importer's native gate does: left unresolved, named in the result; a hand-written law that does
#      the same still does not link.  The proof is added to the upstream in a second commit (the goldens use the first).
U=$T/upstream/toy/cbmc/proofs/undefined_fn
mkdir -p "$U"
printf '# tests/qp/cbmc.sh: the toy proof undefined_fn\nPROOF_UID = undefined_fn\nPROOF_SOURCES += $(HARNESS_FILE)\nPROJECT_SOURCES += $(SRCDIR)/src/toy.c\n\ninclude ../Makefile.common\n' \
  > "$U/Makefile"
cat > "$U/undefined_fn_harness.c" <<'EOF'
/* tests/qp/cbmc.sh: a stub that refers to a function defined nowhere and that the harness never calls (as
   coreMQTT's network stubs refer to the transport). */
#include "toy_cbmc.h"

int toy_transport_send(const void *p, int n);

int toy_stub_send(const void *p, int n)
{
	return toy_transport_send(p, n);
}

void harness(void)
{
	int x;
	__CPROVER_assume(x > 0 && x < 100);
	__CPROVER_assert(toy_twice(x) > x, "twice grows");
}
EOF
(cd "$T/upstream" && "${G[@]}" add -A &&
 GIT_AUTHOR_DATE=2026-01-02T00:00:00Z GIT_COMMITTER_DATE=2026-01-02T00:00:00Z "${G[@]}" commit -qm undefined_fn)
project undef toy
sed -i "s/^COMMIT=.*/COMMIT=$(git -C "$T/upstream" rev-parse HEAD)/" "$WS/projects/undef/project.conf"
run und_imp "${Q[@]}" import-cbmc undef toy/cbmc/proofs/undefined_fn --no-check
cat > "$WS/projects/undef/harness/plain_undef.c" <<'EOF'
/* Law plain_undef: a hand-written law that refers to a function defined nowhere (tests/qp/cbmc.sh). */
#include "quickproof.h"

int defined_nowhere(int x);

int never_called(int x)
{
	return defined_nowhere(x);
}

int main(void)
{
	gp_assert(nondet_u8() < 256);
	return 0;
}
EOF
run und_fuzz "${Q[@]}" fuzz undef -n 50
if [ $rc = 0 ] && has und_imp '^wrote projects/undef/harness/undefined_fn.c' &&
   has und_fuzz '^undefined_fn *upstream *ok (50 runs); unresolved (defined nowhere, as CBMC allows): toy_transport_send$' &&
   has und_fuzz '^plain_undef *upstream *build failed$'; then
  ok "qp fuzz: an imported law whose stub refers to a function defined nowhere links as the native gate does (left unresolved, named); a hand-written one does not"
else bad "qp fuzz of a law with a function defined nowhere"; cat "$T/und_imp.log" "$T/und_fuzz.log"; fi

# ---- nothing written outside the temporary directory (but the Coq library's build products)
new=$(find "$GP" -newer "$T/start" -type f -not -path '*/.git/*' -not -path "$GP/coq/*" -not -path "$EXP/*" | head)
if [ -z "$new" ]; then ok "nothing written in the framework checkout"; else bad "files written in the checkout: $new"; fi
[ "$fails" -eq 0 ]
