#!/usr/bin/env bash
# devcontainer_test.sh [IMAGE]: proving by hand in VS Code, without VS Code.  Brings up ../devcontainer/devcontainer.json
# with the Dev Containers CLI (as VS Code's "Reopen in Container" does), makes a project in it, puts a proof in
# place (as a person would type it), builds it, opens files with coq-lsp through an LSP client (tests/lsp_check.py,
# what the coq-lsp extension does) and runs qp verify on a shipped example and on that proof.
# The image in devcontainer.json is replaced by IMAGE (default quickproof:latest).  Needs node/npx.
# DEVCONTAINER_CLI: the CLI version (0.80.1 hangs after starting the container with Docker 29).  The logs go to
# LOGDIR (default: a new temporary directory).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
IMG=${1:-quickproof:latest}
L=${LOGDIR:-$(mktemp -d "${TMPDIR:-/tmp}/qp-devcontainer-logs.XXXX")}
SOL=$HERE/count_byte_ok
CLI=@devcontainers/cli@${DEVCONTAINER_CLI:-0.89.0}
mkdir -p "$L"
W=$(mktemp -d "${TMPDIR:-/tmp}/qp-devcontainer.XXXX")
mkdir -p "$W/.devcontainer"
sed "s|\"image\": \"[^\"]*\"|\"image\": \"$IMG\"|" "$HERE/../devcontainer/devcontainer.json" > "$W/.devcontainer/devcontainer.json"
fails=0
check() { if "${@:2}"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
dc() { (cd "$W" && npx -y "$CLI" exec --workspace-folder "$W" "$@"); }
echo "# $(date -u +%FT%TZ) $CLI, $IMG; work $W" | tee "$L/summary.txt"
t0=$(date +%s)
(cd "$W" && timeout 600 npx -y "$CLI" up --workspace-folder "$W" > "$L/up.json" 2> "$L/up.log" < /dev/null); rc=$?
check "devcontainer up (rc=$rc, $(( $(date +%s) - t0 )) s)" grep -q '"outcome":"success"' "$L/up.json"
CID=$(python3 -c "import json;print(json.load(open('$L/up.json'))['containerId'][:12])" 2>/dev/null)
dc qpdemo new demo > "$L/new.log" 2>&1
dc qpdemo contract demo > "$L/contract.log" 2>&1
mkdir -p "$W/demo-proof/src/proof"
cp "$SOL"/src/proof/*.v "$W/demo-proof/src/proof/" && cp "$SOL"/src/contracts/*.v "$W/demo-proof/src/contracts/"
t0=$(date +%s); dc qpdemo build demo > "$L/build.log" 2>&1; rc=$?
check "qpdemo build in the devcontainer (rc=$rc, $(( $(date +%s) - t0 )) s)" test $rc -eq 0
lsp() { python3 "$HERE/lsp_check.py" "$@" -- docker exec -i "$CID" coq-lsp; }
{ cat "$W/demo-proof/src/proof/Count.v"; printf '\nLemma broken_on_purpose : 1 + 1 = 3.\nProof. reflexivity. Qed.\n'; } > "$W/demo-proof/src/proof/CountBroken.v"
bad=$(( $(wc -l < "$W/demo-proof/src/proof/CountBroken.v") ))
{ check "coq-lsp: Count.v clean" lsp /work/demo-proof /work/demo-proof/src/proof/Count.v clean
  check "coq-lsp: the contract with the proof clean" lsp /work/demo-proof /work/demo-proof/src/contracts/count_byte_ok.v clean
  check "coq-lsp: a false lemma is reported (line $bad)" lsp /work/demo-proof /work/demo-proof/src/proof/CountBroken.v "error:$bad"
  check "coq-lsp: with /work as the folder _CoqProject is not found (open NAME-proof instead)" \
        lsp /work /work/demo-proof/src/proof/Count.v errors; } 2>&1 | tee "$L/lsp.log"
rm -f "$W/demo-proof/src/proof/CountBroken.v"
for x in rle demo; do
  t0=$(date +%s); dc qpdemo verify $x > "$L/verify-$x.log" 2>&1
  check "qpdemo verify $x in the devcontainer ($(( $(date +%s) - t0 )) s)" grep -q "Verdict: PASS" "$L/verify-$x.log"
done
IMGUID=$(docker inspect -f '{{.Config.Image}}' "$CID" 2>/dev/null)   # the CLI's vsc-*-uid image on top of the demo image
docker rm -f "$CID" > /dev/null
case $IMGUID in vsc-*) docker rmi "$IMGUID" > /dev/null ;; esac
echo "failures: $fails (logs: $L)" | tee -a "$L/summary.txt"
exit $((fails > 0))
