#!/usr/bin/env bash
# quickproof tools/interp.sh CONFIG HARNESS.c [FIRST [RUNS]]: run a harness under CompCert's reference
# interpreter, with the flags of CONFIG (see tools/clight.sh) and runtime/interp_driver.c.
#
# The interpreter executes the Clight semantics the theorem is about, so a "Stuck state" is undefined
# behaviour in that semantics even when native runs and sanitizers are clean.  The units of CONFIG
# (except the harness units under harness/) and the harness are put in one translation unit, which
# `ccomp -interp` requires.  malloc/free are not renamed here: the interpreter provides them.
# GP_ENV=file.c: the project's nondet_* (value distributions, as for runtime/fuzz_driver.c; it must define all four
# of nondet_u8/u32/size/bytes, and they may
# draw from quickproof_rnd()) instead of the driver's generic ones.
set -euo pipefail
CONFIG=$(realpath "$1"); HARNESS=$(realpath "$2"); FIRST=${3:-1}; RUNS=${4:-20}
GP=$(cd "$(dirname "$0")/.." && pwd)
cd "$(dirname "$CONFIG")"
INC=(); DEFS=(); UNITS=(); INTERP_UNITS=()
python3 "$GP/tools/conf.py" "$CONFIG"   # the conf must be data (assignments only) before it is sourced
# shellcheck disable=SC1090
source "$CONFIG"
# INTERP_UNITS, when the conf sets it, replaces the library units of UNITS here (the interpreter only): for code
# whose files cannot share one translation unit as they are, a file that includes them all (the conf is data, so
# it cannot test which tool reads it).
[ ${#INTERP_UNITS[@]} -eq 0 ] || UNITS=("${INTERP_UNITS[@]}")
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
# One translation unit is required, so the file-local names of each unit (static functions and
# variables, and the typedef/struct/union/enum names defined in the .c file itself) are renamed
# with a per-unit prefix around its #include: two units may both define a static st_step or a
# typedef output_info.
local_names() {   # $1 = source file
  # static functions and variables defined in the file itself (as in clight.sh): a static inline
  # function of a shared header must keep its name, or the header's include guard leaves the second
  # unit with calls to an undefined renamed function
  local f; f=$(realpath "$1")
  gcc -c -g -w "${DEFS[@]}" "${INC[@]}" -I"$GP/include" -o "$TMP/o.o" "$1" 2>/dev/null \
    && nm -l "$TMP/o.o" | awk -v f="$f" '$2 ~ /^[tdbr]$/ { split($4, loc, ":"); if (loc[1] == f) print $3 }' \
    | grep -v '\.' || true
  python3 - "$1" <<'PY'
import re, sys
s = open(sys.argv[1], errors='replace').read()
s = re.sub(r'/\*.*?\*/', ' ', s, flags=re.S); s = re.sub(r'//[^\n]*', ' ', s)
names = set(re.findall(r'\b(?:struct|union|enum)\s+(\w+)\s*\{', s))
depth = 0; top = []
for ch in s:
    if ch == '{': depth += 1
    elif ch == '}': depth -= 1
    top.append(ch if depth == 0 or ch == '}' else ' ')
for m in re.finditer(r'\btypedef\b[^;]*?(\w+)\s*(?:\[[^\]]*\])?\s*;', ''.join(top)):
    names.add(m.group(1))
print('\n'.join(sorted(names)))
PY
}
{
  i=0
  for u in "${UNITS[@]}"; do
    src=$(realpath "${u%%=*}")
    [ "$src" = "$HARNESS" ] && continue
    case $src in */harness/*) continue;; esac
    i=$((i + 1))
    names=$(local_names "$src" | sort -u)
    for n in $names; do echo "#define $n gp_u${i}_$n"; done
    echo "#include \"$src\""
    for n in $names; do echo "#undef $n"; done
  done
  echo "#define main harness_main"
  echo "#include \"$HARNESS\""
  echo "#undef main"
  if [ -n "${GP_ENV:-}" ]; then echo "#define GP_CUSTOM_NONDET 1"; fi
  echo "#include \"$GP/runtime/interp_driver.c\""
  if [ -n "${GP_ENV:-}" ]; then echo "#undef rnd"; echo "#include \"$(realpath "$GP_ENV")\""; fi
} > "$TMP/unity.c"
# One seed per `ccomp -interp` invocation, under a timeout, so a seed that diverges (a false
# gp_assume spins in for(;;), or any safe non-terminating run) is isolated instead of hanging the
# whole sweep.  unity.c is built ONCE above; only -DGP_FIRST differs per invocation (-DGP_RUNS=1).
# Exit status of each timeout'd run:
#   124      timeout => that seed diverged: a SAFE non-terminating run (divergence is safe under
#            partial correctness, not a finding).  Count it skipped and go on to the next seed.
#   0        ran clean.
#   other    ccomp -interp hit a Stuck state / error => a genuine counterexample to harness_safe:
#            print the seed and the tail of ccomp's output, and STOP.
skipped=0; stuck=0
for seed in $(seq "$FIRST" $((FIRST + RUNS - 1))); do
  set +e
  out=$(timeout "${GP_INTERP_TIMEOUT:-10}s" \
    ccomp -interp -quiet -fstruct-passing -DGP_FIRST="$seed" -DGP_RUNS=1 "${DEFS[@]}" "${INC[@]}" \
    -I"$GP/include" "$TMP/unity.c" 2>&1)
  rc=$?
  set -e
  if [ "$rc" -eq 124 ]; then
    skipped=$((skipped + 1))
    continue
  elif [ "$rc" -ne 0 ]; then
    echo "seed $seed: Stuck state / error (ccomp -interp exit $rc) -- counterexample to harness_safe"
    echo "$out" | tail -n 6
    stuck=1
    break
  fi
done
if [ "$stuck" -ne 0 ]; then exit 1; fi
echo "runs $RUNS: no stop ($skipped skipped: gp_assume or safe non-termination)"
