#!/usr/bin/env bash
# host_agent_test.sh [IMAGE]: an agent on the host, without an agent.  A container runs `qpdemo serve` with a host directory
# mounted at the same path; "the agent" works on the host: it writes the proof files there, talks to the MCP
# server through `docker exec -i CONTAINER rocq-mcp` with a plain stdio client (tests/mcp_stdio_client.py), and
# builds and verifies through `docker exec CONTAINER qpdemo ...`.  The proof is a known proof of the template
# law (count_byte_ok/; an agent would write it).  Exit 0 = every step as expected.  The logs go to LOGDIR
# (default: a new temporary directory).
set -uo pipefail
IMG=${1:-quickproof:latest}
HERE=$(cd "$(dirname "$0")" && pwd)
L=${LOGDIR:-$(mktemp -d "${TMPDIR:-/tmp}/qp-host-agent-logs.XXXX")}
SOL=$HERE/count_byte_ok
mkdir -p "$L"
W=$(mktemp -d "${TMPDIR:-/tmp}/qp-host-agent.XXXX")
C=qp-host-agent-test-$$
fails=0
check() { if "${@:2}"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
echo "# $(date -u +%FT%TZ) $IMG; work $W" | tee "$L/summary.txt"

docker run -d --name "$C" -v "$W:$W" -e QP_WORK="$W" -w "$W" "$IMG" serve > /dev/null
sleep 2
docker logs "$C" > "$L/serve.log" 2>&1
check "serve prints how to connect" grep -q 'docker exec -i <container> rocq-mcp' "$L/serve.log"
docker exec "$C" qpdemo new demo > "$L/new.log" 2>&1
docker exec "$C" qpdemo contract demo > "$L/contract.log" 2>&1
check "the proving repository is on the host at the same path" test -f "$W/demo-proof/AGENTS.md"
check "the worked examples are readable on the host (quickproof/examples)" test -f "$W/demo-proof/quickproof/examples/rle/proof/src/proof/Decode.v"
# "the agent" edits on the host
mkdir -p "$W/demo-proof/src/proof" && cp "$SOL"/src/proof/*.v "$W/demo-proof/src/proof/"
t0=$(date +%s); docker exec "$C" qpdemo build demo > "$L/build.log" 2>&1; rc=$?
check "build through docker exec (rc=$rc, $(( $(date +%s) - t0 )) s)" test $rc -eq 0
python3 "$HERE/mcp_stdio_client.py" "$W/demo-proof" -- docker exec -i "$C" rocq-mcp > "$L/mcp.log" 2>&1; rc=$?
cat "$L/mcp.log"
check "plain MCP client over docker exec -i (rc=$rc)" test $rc -eq 0
docker exec -i "$C" /opt/rocq-mcp/bin/python - "$W/demo-proof" < "$HERE/mcp_smoke.py" > "$L/mcp-smoke.log" 2>&1; rc=$?
cat "$L/mcp-smoke.log"
check "fastmcp client in the container, as Claude Code there (rc=$rc)" test $rc -eq 0
cp "$SOL"/src/contracts/*.v "$W/demo-proof/src/contracts/"
t0=$(date +%s); docker exec "$C" qpdemo verify demo > "$L/verify.log" 2>&1; rc=$?
check "verify through docker exec: PASS (rc=$rc, $(( $(date +%s) - t0 )) s)" grep -q 'Verdict: PASS' "$L/verify.log"
check "files written in the container are the host user's" test "$(stat -c %u "$W/demo-proof/src/proof/Count.vo" 2>/dev/null)" = "$(id -u)"
t0=$(date +%s); docker stop "$C" > /dev/null; docker rm "$C" > /dev/null
check "docker stop ends serve at once ($(( $(date +%s) - t0 )) s)" test $(( $(date +%s) - t0 )) -lt 8
echo "failures: $fails (logs: $L)" | tee -a "$L/summary.txt"
exit $((fails > 0))
