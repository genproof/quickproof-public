#!/usr/bin/env bash
# quickproof tools/clight.sh CONFIG: translate C units to Clight ASTs (code.v) for VST.
#
# CONFIG is a bash file, read relative to its own directory, that sets
#   INC=(-I... ...)                 include flags
#   DEFS=(-D... ...)                preprocessor flags
#   UNITS=("src.c=out/dir" ...)     each unit becomes out/dir/code.v
#
# Every unit is built with clightgen -normalize and -Dmalloc=quickproof_malloc -Dfree=quickproof_free:
# a preprocessor renaming (no source edit) after which malloc/free are plain externals, covered by
# the honest environment QuickProof.Env (add_funspecs covers only EF_external, not CompCert's
# EF_malloc/EF_free).  The framework's include/ is on the include path (quickproof.h).
set -euo pipefail
CONFIG=$(realpath "$1")
GP=$(cd "$(dirname "$0")/.." && pwd)
cd "$(dirname "$CONFIG")"
INC=(); DEFS=(); UNITS=()
python3 "$GP/tools/conf.py" "$CONFIG"   # the conf must be data (assignments only) before it is sourced
# shellcheck disable=SC1090
source "$CONFIG"
ALLOC=(-Dmalloc=quickproof_malloc -Dfree=quickproof_free)
# clightgen keeps a static function or variable under its plain name, so two units with different
# statics of the same name cannot be linked (VST's QPlink: "internal function clash", for example when
# the encoder and the decoder of one library both have a static helper of the same name).  Such names
# are renamed per unit (-Dname=<unit>__name): static linkage makes the name private to the unit, so the
# program is the same.  Only statics defined in the unit's own .c file are candidates: a static inline
# function of a shared header is the same in every unit that includes it, and QPlink accepts identical
# copies.  Names static in only one unit are left alone.
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
statics() {   # $1 = source file: the static functions and variables defined in it (not in a header)
  local f; f=$(realpath "$1")
  gcc -c -g -w "${ALLOC[@]}" "${DEFS[@]}" "${INC[@]}" -I"$GP/include" -o "$TMP/o.o" "$1" \
    && nm -l "$TMP/o.o" | awk -v f="$f" '$2 ~ /^[tdbr]$/ { split($4, loc, ":"); if (loc[1] == f) print $3 }' \
    | grep -v '\.' | sort -u || true
}
# A clash is a static defined in two library units, or in a library unit and a harness: every harness
# is linked with all library units but never with another harness, so two harnesses may share a name.
for u in "${UNITS[@]}"; do case ${u#*=} in src/harness/*) ;; *) statics "${u%%=*}";; esac; done | sort > "$TMP/lib"
for u in "${UNITS[@]}"; do case ${u#*=} in src/harness/*) statics "${u%%=*}";; esac; done | sort -u > "$TMP/harn"
{ uniq -d "$TMP/lib"; sort -u "$TMP/lib" | comm -12 - "$TMP/harn"; } | sort -u > "$TMP/clash"
for u in "${UNITS[@]}"; do
  src=${u%%=*}; out=${u#*=}
  unit=$(basename "$out" | tr -c 'A-Za-z0-9_\n' '_')
  RENAME=()
  for n in $(statics "$src" | comm -12 - "$TMP/clash"); do RENAME+=("-D$n=${unit}__$n"); done
  mkdir -p "$out"
  echo "clightgen $src -> $out/code.v${RENAME:+ (renamed statics: ${RENAME[*]#-D})}"
  # Preprocess, tag the typedef'd anonymous composites (tools/tag_anon.py), then translate.
  i="$TMP/$unit.i"
  clightgen -E "${ALLOC[@]}" "${DEFS[@]}" "${RENAME[@]}" "${INC[@]}" -I"$GP/include" "$src" > "$i"
  python3 "$GP/tools/tag_anon.py" "$i"
  clightgen -normalize "$i" -o "$out/code.v"
  # record the source file, not the temporary preprocessed one (reproducible output)
  rel=$(realpath -m --relative-to=. "$src")   # relative to the conf's directory: no local path in a proof repository
  sed -i "s|^  Definition source_file := \".*\"\.|  Definition source_file := \"$rel\".|" "$out/code.v"
  # clightgen names string literals __stringlit_N, numbered per unit: two units with literals would
  # define the same global (QPlink: "Gvars both initialized").  They are private to the unit, so a
  # per-unit name is the same program (two configurations of one file, for example).
  sed -i "s/__stringlit_/__stringlit_${unit}_/g" "$out/code.v"
done
# An anonymous struct/union shared by units gets one name in all of them (tools/canon_anon.py).
OUTS=(); for u in "${UNITS[@]}"; do OUTS+=("${u#*=}/code.v"); done
python3 "$GP/tools/canon_anon.py" "${OUTS[@]}"
