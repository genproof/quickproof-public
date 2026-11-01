#!/usr/bin/env bash
# prove_fake.sh [IMAGE]: tests `qpdemo prove` and `qpdemo agent setup` without a key or a real agent.  A fake
# `claude` (tests/fake-claude/claude) is mounted where `qpdemo agent setup` would install the real one, in a
# volume-like directory on /home/opam/.local.  Three scenes:
#   1. agent setup refuses without a confirmation (no terminal, no --yes);
#   2. solve2: round 1 leaves the theorem Admitted (the judge fails), round 2 finishes it (the judge passes):
#      the loop, the resumed session, the judge, and the flags qpdemo passes to claude;
#   3. stuck: the agent never proves anything; a budget of 7 turns ends the run after rounds of 3, 3 and 1 turns.
# The fake agent copies a known proof of the template's law (count_byte_ok/, written by an AI agent in a run of
# `qpdemo prove`).  Exit 0 = all scenes as expected.  The logs go to LOGDIR (default: a new temporary directory).
set -uo pipefail
IMG=${1:-quickproof:latest}
HERE=$(cd "$(dirname "$0")" && pwd)
L=${LOGDIR:-$(mktemp -d "${TMPDIR:-/tmp}/qp-prove-fake-logs.XXXX")}
SOL=$HERE/count_byte_ok
mkdir -p "$L"
W=$(mktemp -d "${TMPDIR:-/tmp}/qp-prove-fake.XXXX")
AG=$(mktemp -d "${TMPDIR:-/tmp}/qp-agent-home.XXXX")   # stands for the volume on /home/opam/.local
mkdir -p "$AG/bin" && cp "$HERE/fake-claude/claude" "$AG/bin/claude" && chmod 755 "$AG/bin/claude"
chmod 777 "$W" "$AG" "$AG/bin"
fails=0
check() {   # check DESCRIPTION COMMAND...: pass/fail line
  if "${@:2}"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}
run() { docker run --rm -v "$W:/work" -v "$AG:/home/opam/.local" -v "$SOL:/solution:ro" \
          -e FAKE_CLAUDE_LOG=/work/fake-claude.log "$@"; }

echo "# $(date -u +%FT%TZ) $IMG; work $W" | tee "$L/summary.txt"

# 1. setup needs a confirmation
docker run --rm "$IMG" agent setup < /dev/null > "$L/setup-noconfirm.log" 2>&1; rc=$?
check "agent setup without -it and --yes refuses (rc=$rc)" test $rc -ne 0
check "agent setup says where it downloads from" grep -q 'curl -fsSL https://claude.ai/install.sh | bash' "$L/setup-noconfirm.log"
check "agent setup says it needs a confirmation" grep -q 'needs your confirmation' "$L/setup-noconfirm.log"
docker run --rm "$IMG" prove demo > "$L/prove-noclaude.log" 2>&1; rc=$?
check "prove without Claude Code points to agent setup (rc=$rc)" grep -q 'qpdemo agent setup' "$L/prove-noclaude.log"

# 2. solve2
run "$IMG" new demo > "$L/new.log" 2>&1
run "$IMG" contract demo > "$L/contract.log" 2>&1
check "the contract has AGENTS.md with the theorem filled in" grep -q '`count_byte_ok`' "$W/demo-proof/AGENTS.md"
check "AGENTS.md points to the framework's examples" grep -q 'quickproof/examples/' "$W/demo-proof/AGENTS.md"
check "the examples are in the repository (quickproof/examples)" test -f "$W/demo-proof/quickproof/examples/find_byte/proof/src/proof/Find.v"
check "AGENTS.md is part of the contract commit" bash -c "git -C '$W/demo-proof' show contract --stat | grep -q AGENTS.md"
t0=$(date +%s)
run -e FAKE_CLAUDE_MODE=solve2 "$IMG" prove demo --budget-turns 20 > "$L/prove-solve2.log" 2>&1; rc=$?
echo "solve2: rc=$rc, $(( $(date +%s) - t0 )) s" | tee -a "$L/summary.txt"
check "solve2 ends with PASS (rc=$rc)" test $rc -eq 0
check "solve2: the judge failed after round 1" bash -c "grep -A40 'round 1 ended' '$L/prove-solve2.log' | grep -q 'Verdict: FAIL'"
check "solve2: round 2 resumed the session" grep -q '== round 2: resumed' "$L/prove-solve2.log"
check "solve2: the judge passed after round 2" grep -q 'Verdict: PASS' "$L/prove-solve2.log"
check "solve2: summary counts 4 turns" grep -q '^- turns: 4 tool-use round trips' "$L/prove-solve2.log"
check "solve2: PROVE.md written" test -s "$W/demo-proof/run/qpdemo/PROVE.md"
check "solve2: the fake claude saw no problem with the flags" bash -c "! grep -q '\"problems\": \[\"' '$W/fake-claude.log'"
check "solve2: the MCP config started rocq-mcp (rocq_start listed)" grep -q '"rocq_start"' "$W/fake-claude.log"
check "solve2: --max-turns 20 then 18" bash -c "grep -o '\"max_turns\": [0-9]*' '$W/fake-claude.log' | tr '\n' ' ' | grep -q '20 .*18'"
cp "$W/fake-claude.log" "$L/fake-claude-solve2.log"

# 3. stuck: the budget ends it (in a second work directory, where the law's name is unique)
run "$IMG" new demo2 > /dev/null 2>&1
run "$IMG" prove count_byte_ok > "$L/prove-ambiguous.log" 2>&1
check "a law name in two projects is refused" grep -q 'is in several projects: demo, demo2' "$L/prove-ambiguous.log"
W2=$(mktemp -d "${TMPDIR:-/tmp}/qp-prove-fake2.XXXX"); chmod 777 "$W2"
run2() { docker run --rm -v "$W2:/work" -v "$AG:/home/opam/.local" -e FAKE_CLAUDE_LOG=/work/fake-claude.log "$@"; }
run2 "$IMG" new demo2 > /dev/null 2>&1
t0=$(date +%s)
run2 -e FAKE_CLAUDE_MODE=stuck "$IMG" prove count_byte_ok --budget-turns 7 > "$L/prove-stuck.log" 2>&1; rc=$?
echo "stuck: rc=$rc, $(( $(date +%s) - t0 )) s" | tee -a "$L/summary.txt"
check "stuck: no repository yet, so prove ran qpdemo contract first" grep -q 'no proving repository yet: qpdemo contract demo2' "$L/prove-stuck.log"
check "stuck ends NOT PROVED (rc=$rc)" test $rc -eq 1
check "stuck: the budget ended it" grep -q 'NOT PROVED count_byte_ok: the turn budget (7) is used up' "$L/prove-stuck.log"
check "stuck: --max-turns 7, 4, 1 over three rounds" bash -c "grep -o '\"max_turns\": [0-9]*' '$W2/fake-claude.log' | grep -o '[0-9]*$' | tr '\n' ' ' | grep -qx '7 4 1 '"
check "stuck: the law name resolved to the project demo2" grep -q 'demo2-proof' "$L/prove-stuck.log"
cp "$W2/fake-claude.log" "$L/fake-claude-stuck.log"

echo "work dir: $W" >> "$L/summary.txt"
echo "failures: $fails (logs: $L)" | tee -a "$L/summary.txt"
exit $((fails > 0))
