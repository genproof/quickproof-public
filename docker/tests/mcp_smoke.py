"""mcp_smoke.py REPO: drives the MCP server rocq-mcp (LLM4Rocq) inside the image through the fastmcp client, the
way an agent in the container does (Claude Code under `qpdemo prove` starts `rocq-mcp` over stdio), on a built
QuickProof proving repository with a proof file in src/proof/ (its first .v file):
  - tools/list and rocq_health (coqc, pet);
  - rocq_toc and rocq_compile_file with keep_vo (the .vo stays for the files that import it);
  - an interactive session on the body lemma: rocq_start, the goals after `start_function. forward.`,
    rocq_step_multi, and a wrong tactic reported as an error with a state to go on from;
  - a small lemma replayed to the end: proof_finished, and the tactics of the proof;
  - rocq_query (Search) in the file's context, and Print Assumptions of the body lemma.
Run with the rocq-mcp venv's python, e.g.
  docker exec -i CONTAINER /opt/rocq-mcp/bin/python - /work/demo-proof < docker/tests/mcp_smoke.py
Exit 0 when every step gives what it should."""
import asyncio
import json
import os
import re
import sys
import time

from fastmcp import Client
from fastmcp.client.transports import StdioTransport

REPO = os.path.abspath(sys.argv[1])
PROOF_DIR = os.path.join(REPO, 'src', 'proof')
FILE = os.path.join(PROOF_DIR, sorted(f for f in os.listdir(PROOF_DIR) if f.endswith('.v'))[0])
TEXT = open(FILE).read()
BODY = re.search(r'^Lemma (body_\w+)', TEXT, re.M).group(1)
# a lemma whose proof is one line `Proof. TACTICS Qed.`, to replay to the end
SMALL = re.search(r'^Lemma (\w+)\b[^.]*(?:\.[^\n]+)?\n?Proof\. (.+?) Qed\.', TEXT, re.M)
fails = 0


def data(r):
    d = getattr(r, 'data', None)
    if d is None:
        d = getattr(r, 'structured_content', None)
    if d is None:
        try:
            d = json.loads(''.join(getattr(c, 'text', '') for c in r.content))
        except ValueError:
            d = {}
    return d if isinstance(d, dict) else {'value': d}


def step(label, ok, detail=''):
    global fails
    fails += 0 if ok else 1
    print('%s %-36s %s' % ('ok  ' if ok else 'FAIL', label, ' '.join(str(detail).split())[:170]), flush=True)


async def call(c, tool, **args):
    t = time.time()
    d = data(await c.call_tool(tool, args, raise_on_error=False))
    return d, time.time() - t


async def main():
    t = StdioTransport(command='/usr/local/bin/rocq-mcp', args=[], cwd=REPO)
    async with Client(t, timeout=900) as c:
        tools = sorted(x.name for x in await c.list_tools())
        step('tools/list', {'rocq_start', 'rocq_check', 'rocq_step_multi', 'rocq_compile_file', 'rocq_query'} <= set(tools),
             '%d tools' % len(tools))
        h, dt = await call(c, 'rocq_health')
        step('rocq_health', h.get('success') is not False, 'coqc and pet: %s (%.1f s)' % (
            {k: v for k, v in h.items() if 'coq' in k or 'pet' in k or 'version' in k}, dt))
        toc, dt = await call(c, 'rocq_toc', file=FILE)
        step('rocq_toc ' + os.path.basename(FILE), BODY in json.dumps(toc), '(%.1f s)' % dt)
        vo = FILE + 'o'
        if os.path.exists(vo):
            os.remove(vo)
        comp, dt = await call(c, 'rocq_compile_file', file=FILE, keep_vo=True)
        step('rocq_compile_file keep_vo=true', comp.get('success') is True and os.path.exists(vo), '(%.1f s)' % dt)

        st, dt = await call(c, 'rocq_start', file=FILE, theorem=BODY)
        sid = st.get('state_id')
        step('rocq_start ' + BODY, sid is not None and 'semax_body' in json.dumps(st.get('goals')),
             'state %s (%.1f s)' % (sid, dt))
        ck, dt = await call(c, 'rocq_check', body='start_function. forward.', from_state=sid)
        goals = json.dumps(ck.get('goals'))
        step('rocq_check start_function. forward.', ck.get('state_id') is not None and 'semax' in goals,
             'the goal is a VST triple again (%.1f s)' % dt)
        sm, dt = await call(c, 'rocq_step_multi', tactics=['forward.', 'entailer!.', 'lia.'], from_state=ck.get('state_id'))
        res = sm.get('results') or []
        step('rocq_step_multi 3 tactics', len(res) == 3,
             ', '.join('%s %s' % (x.get('tactic'), 'ok' if x.get('success') else 'fails') for x in res) + ' (%.1f s)' % dt)
        bad, dt = await call(c, 'rocq_check', body='exact I.', from_state=ck.get('state_id'))
        step('rocq_check a wrong tactic', bad.get('success') is False and bool(bad.get('error')),
             '%s (%.1f s)' % (str(bad.get('error'))[:90], dt))

        if SMALL:
            name, script = SMALL.group(1), SMALL.group(2)
            s0, _ = await call(c, 'rocq_start', file=FILE, theorem=name)
            fin, dt = await call(c, 'rocq_check', body=script, from_state=s0.get('state_id'))
            step('replay %s to the end' % name, fin.get('proof_finished') is True,
                 'proof_finished, tactics %s (%.1f s)' % (fin.get('proof_tactics'), dt))
        else:
            step('replay a one-line lemma', False, 'no one-line lemma in ' + FILE)

        q, dt = await call(c, 'rocq_query', command='Search Znth map.', file=FILE, max_results=5)
        step('rocq_query Search Znth map.', 'Znth_map' in json.dumps(q), '(%.1f s)' % dt)
        a, dt = await call(c, 'rocq_assumptions', name=BODY, file=FILE)
        txt = json.dumps(a)
        step('rocq_assumptions ' + BODY, a.get('success') is not False and 'Admitted' not in txt,
             '%s (%.1f s)' % (txt[:120], dt))
    print('failures: %d' % fails)
    return fails


sys.exit(1 if asyncio.run(main()) else 0)
