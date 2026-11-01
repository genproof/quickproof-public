#!/usr/bin/env bash
# quickproof tests/run.sh: the framework's own tests.  Needs the toolchain (Coq 8.20.1, VST 2.15, CompCert 3.15;
# e.g. `eval $(opam env --switch=quickproof)`, as in the README).  Writes only in a temporary directory and in coq/
# (the library's build products).  Exit 0 iff every test passes.
#
#  1. the Coq library builds (QuickProof.Link: honest_rejects_foreign; QuickProof.Assembly);
#     nondet_bytes(NULL, 0) is legal in the theorem and in the drivers (tests/check-env-empty.sh);
#  2. LINK=all (the default): the generated contracts of the toy project are byte-identical to the golden
#     files written by an earlier release of the generator;
#  2b. qp_assert/qp_assume, the macros of quickproof.h, give the same Clight as gp_assert/gp_assume;
#  3. LINK=per-law: tools/link_units.py gives the expected unit lists; the contracts build, with their check
#     of the undefined globals;
#  4. a toy suite of two laws on per-law programs, proved from one shared library (tests/perlaw/proof):
#     Qed, and Print Assumptions shows only standard axioms and VST's malloc library;
#  5. rejections: an override UNITS_<law> that leaves out a unit the law needs (its harness calls a function
#     of that unit) writes no contract; a contract whose link leaves out such a unit does not build; a
#     program of all units that defines a function twice differently is refused; a bad LINK value is refused;
#     a unit that defines a function of the environment is refused.
#  6. tools/qp (tests/qp.sh): the Clight audit, the VST lint, templates, and every subcommand end to end
#     on a toy workspace made of this project's toy (offline).
#  7. the examples (examples/): `tools/qp examples` checks each shipped proof as qp verify does; all PASS.
set -euo pipefail
GP=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fails=$((fails + 1)); }
quiet() { "$@" > "$T/last.log" 2>&1; }
toy() {   # a fresh copy of the toy project in $T/$1, translated with clight.sh
  rm -rf "${T:?}/$1"; mkdir -p "$T/$1"
  cp -r "$GP/tests/perlaw/lib" "$GP/tests/perlaw/harness" "$GP/tests/perlaw/quickproof.conf" \
        "$GP/tests/perlaw/_CoqProject" "$GP/tests/perlaw/proof" "$T/$1/"
  ln -s "$GP" "$T/$1/quickproof"
  (cd "$T/$1" && quiet bash quickproof/tools/clight.sh quickproof.conf)
}
build() {  # build targets in a toy copy
  (cd "$T/$1" && coq_makefile -f _CoqProject -o CoqMakefile > /dev/null 2>&1 && shift && make -f CoqMakefile "$@")
}

# 1. the Coq library
if (cd "$GP/coq" && coq_makefile -f _CoqProject -o Makefile.coq > /dev/null 2>&1 && quiet make -f Makefile.coq -j4); then
  ok "coq library (Env, Contract, EnvBodies, Pick, Link, Assembly)"
else bad "coq library"; tail -20 "$T/last.log"; fi

# 1b. the environment's names agree: tools/link_units.py's ENV and QuickProof.Link's env_signatures (which
#     env_signatures_spec ties to Env.v's env_specs, by reflexivity)
py=$(python3 -c "import sys; sys.dont_write_bytecode = True; sys.path.insert(0, '$GP/tools'); import link_units; print(' '.join(sorted(link_units.ENV)))")
coq=$(sed -n '/^Definition env_signatures/,/\]\./p' "$GP/coq/QuickProof/Link.v" | grep -o '("[a-z_0-9]*"' | tr -d '("' | sort | tr '\n' ' ' | sed 's/ $//')
if [ "$py" = "$coq" ]; then ok "environment names agree (link_units.ENV, QuickProof.Link.env_signatures)"
else bad "environment names differ: link_units [$py], Link.v [$coq]"; fi

# 1c. nondet_bytes(NULL, 0): proved legal against Env.v (tests/EnvEmpty.v), and run natively and under the
#     interpreter (tests/env_empty.c)
if quiet bash "$GP/tests/check-env-empty.sh"; then
  ok "nondet_bytes(NULL, 0): proved legal, non-NULL contract unchanged; native and interpreter runs touch no memory"
else bad "nondet_bytes(NULL, 0) (tests/check-env-empty.sh)"; tail -20 "$T/last.log"; fi

# 2. LINK=all: byte-identical to the released generator's output
toy all
sed -i '/^LINK=/d' "$T/all/quickproof.conf"
(cd "$T/all" && quiet python3 quickproof/tools/new_contract.py quickproof.conf Toy)
if diff -r "$GP/tests/perlaw/golden-link-all/contracts" "$T/all/src/contracts" > "$T/d" &&
   diff "$GP/tests/perlaw/golden-link-all/units.v" "$T/all/src/units.v" >> "$T/d" && [ ! -e "$T/all/src/units" ]; then
  ok "LINK=all: contracts and src/units.v byte-identical to the released generator's"
else bad "LINK=all: output differs from the released generator's"; head -20 "$T/d"; fi

# 2b. qp_assert and qp_assume (quickproof.h's macros) give the same Clight as gp_assert and gp_assume
toy gpnames
toy qpnames
sed -i -E 's/\bgp_(assert|assume)\b/qp_\1/g' "$T"/qpnames/harness/*.c
(cd "$T/qpnames" && quiet bash quickproof/tools/clight.sh quickproof.conf)
if grep -q 'qp_assert' "$T"/qpnames/harness/*.c && ! grep -q 'gp_assert' "$T"/qpnames/harness/*.c &&
   diff -r -I '^  Definition source_file := ' "$T/gpnames/src" "$T/qpnames/src" > "$T/d"; then
  ok "qp_assert/qp_assume: the same Clight as gp_assert/gp_assume"
else bad "qp_assert/qp_assume: the Clight differs from gp_assert/gp_assume"; head -20 "$T/d"; fi

# 3. LINK=per-law: unit lists, contracts
toy pl
(cd "$T/pl" && python3 quickproof/tools/link_units.py quickproof.conf) > "$T/units.txt" 2>&1 || true
if diff "$GP/tests/perlaw/expected-units.txt" "$T/units.txt" > "$T/d"; then ok "link_units.py: expected unit lists"
else bad "link_units.py unit lists"; cat "$T/d"; fi
(cd "$T/pl" && quiet python3 quickproof/tools/new_contract.py quickproof.conf Toy)
if [ ! -e "$T/pl/src/units.v" ] && [ -f "$T/pl/src/units/Counter.v" ] &&
   grep -q '^Require Toy.units.Counter.$' "$T/pl/src/contracts/law_count.v" &&
   ! grep -q 'Toy.units.Pair' "$T/pl/src/contracts/law_count.v" &&
   grep -q 'Toy.units.Pair' "$T/pl/src/contracts/law_pair.v"; then
  ok "per-law contracts: one file per unit, law_count does not link pair.c"
else bad "per-law contracts layout"; fi
if quiet build pl src/contracts/law_count.vo src/contracts/law_pair.vo src/contracts/suite.vo; then
  ok "per-law contracts build (whole_prog_undefined checked)"
else bad "per-law contracts do not build"; tail -20 "$T/last.log"; fi

# 4. the toy suite: two laws, one shared library
if quiet build pl proof/Suite.vo; then
  ax=$(sed -n '/^Axioms:/,$p' "$T/last.log" | grep -E '^[A-Za-z_.]+ :' | sed 's/ :.*//' | sort -u | tr '\n' ' ')
  allowed='ClassicalDedekindReals.sig_not_dec ClassicalDedekindReals.sig_forall_dec Axioms.prop_ext lib.Axioms.proof_irr
           library.mem_mgr library.malloc_token FunctionalExtensionality.functional_extensionality_dep
           Eqdep.Eq_rect_eq.eq_rect_eq Classical_Prop.classic Ensembles.Extensionality_Ensembles'
  extra=$(for a in $ax; do case " $(echo $allowed) " in *" $a "*) ;; *) echo "$a";; esac; done)
  if [ -n "$ax" ] && [ -z "$extra" ] && ! grep -rqE '\b(Admitted|admit)\b' "$T/pl/proof"; then
    ok "toy suite proved (two per-law programs, one shared library); axioms: standard + VST malloc library"
  else bad "toy suite: unexpected axioms or Admitted: $extra"; fi
else bad "toy suite does not build"; tail -30 "$T/last.log"; fi

# 5a. an override that leaves out a unit the law needs: no contract
toy ov
echo 'UNITS_law_pair=(src/counter src/log)' >> "$T/ov/quickproof.conf"
if (cd "$T/ov" && python3 quickproof/tools/new_contract.py quickproof.conf Toy) > "$T/ov.log" 2>&1; then
  bad "override without pair.c accepted"
elif grep -q 'UNITS_law_pair leaves out src/pair' "$T/ov.log" && [ ! -e "$T/ov/src/contracts" ]; then
  ok "override leaving out pair.c (law_pair calls pair_sum) refused, no contract written"
else bad "override refusal message"; cat "$T/ov.log"; fi
# an override that adds a unit is accepted and recorded
toy ov2
echo 'UNITS_law_count=(src/counter src/log src/big)' >> "$T/ov2/quickproof.conf"
if (cd "$T/ov2" && quiet python3 quickproof/tools/new_contract.py quickproof.conf Toy) &&
   grep -q 'fixed by UNITS_law_count' "$T/ov2/src/contracts/law_count.v" && grep -q 'Toy.units.Big' "$T/ov2/src/contracts/law_count.v"; then
  ok "override adding big.c accepted and recorded"
else bad "override adding a unit"; fi

# 5b. a contract whose link leaves out a needed unit (log.c) does not build: whole_prog_undefined fails
toy cut
(cd "$T/cut" && quiet python3 quickproof/tools/new_contract.py quickproof.conf Toy)
c="$T/cut/src/contracts/law_count.v"
sed -i -e '/^Definition link_Log /d' -e 's/QPlink_progs Harness.qp link_Log/QPlink_progs Harness.qp Counter.qp/' "$c"
line=$(grep -n '^Proof. vm_compute. reflexivity. Qed.$' "$c" | cut -d: -f1)
if ! grep -q 'link_Log' "$c" && ! quiet build cut src/contracts/law_count.vo &&
   grep -q "law_count.v\", line $line,.*" "$T/last.log" && grep -q 'Unable to unify "true" with "false"' "$T/last.log"; then
  ok "contract linking counter.c without log.c (log_reset becomes an external) fails its Coq check"
else bad "contract without log.c built"; tail -10 "$T/last.log"; fi

# 5c. a function defined twice differently in the program of all units; 5d. a bad LINK value
toy dup
printf 'unsigned counter_get(void *c) { return 7; }\n' > "$T/dup/lib/dup.c"
sed -i 's|^  "lib/big.c=src/big"|&\n  "lib/dup.c=src/dup"|' "$T/dup/quickproof.conf"
(cd "$T/dup" && quiet bash quickproof/tools/clight.sh quickproof.conf) || true
if ! (cd "$T/dup" && python3 quickproof/tools/new_contract.py quickproof.conf Toy) > "$T/dup.log" 2>&1 &&
   grep -q 'counter_get is defined differently' "$T/dup.log"; then ok "a function defined by two units refused"
else bad "duplicate definition"; cat "$T/dup.log"; fi
toy lk
sed -i 's/^LINK=per-law/LINK=perlaw/' "$T/lk/quickproof.conf"
if ! (cd "$T/lk" && python3 quickproof/tools/new_contract.py quickproof.conf Toy) > "$T/lk.log" 2>&1 &&
   grep -q 'LINK=perlaw' "$T/lk.log"; then ok "bad LINK value refused"
else bad "bad LINK value"; cat "$T/lk.log"; fi

# 5e. a unit that defines a function of the environment (its names are reserved under per-law linking)
toy envdef
printf '#include <stdint.h>\nuint8_t nondet_u8(void) { return 0; }\n' > "$T/envdef/lib/fake_env.c"
sed -i 's|^  "lib/big.c=src/big"|&\n  "lib/fake_env.c=src/fake_env"|' "$T/envdef/quickproof.conf"
(cd "$T/envdef" && quiet bash quickproof/tools/clight.sh quickproof.conf) || true
if ! (cd "$T/envdef" && python3 quickproof/tools/new_contract.py quickproof.conf Toy) > "$T/envdef.log" 2>&1 &&
   grep -q 'defines nondet_u8, a function of the environment' "$T/envdef.log"; then
  ok "a unit defining a function of the environment refused"
else bad "environment name reservation"; cat "$T/envdef.log"; fi

# 6. tools/qp
if bash "$GP/tests/qp.sh"; then ok "tools/qp (tests/qp.sh)"; else bad "tools/qp (tests/qp.sh)"; fi

# 7. the examples: each proof of examples/ assembled, committed and checked by qp verify, with this framework
if (export QP_CACHE=$T/cache QP_SITE_CONF=/dev/null; unset QP_WORKSPACE QP_FRAMEWORK_DIR QP_TEMPLATES
    "$GP/tools/qp" examples) > "$T/examples.log" 2>&1; then
  ok "examples: $(grep -c '^PASS examples/' "$T/examples.log") proofs checked by qp verify (tools/qp examples)"
else bad "examples (tools/qp examples)"; grep -E '^(PASS|FAIL) ' "$T/examples.log"; tail -30 "$T/examples.log"; fi

echo
if [ "$fails" -eq 0 ]; then echo "all tests passed"; else echo "$fails test(s) FAILED"; exit 1; fi
