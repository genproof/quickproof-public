#!/usr/bin/env python3
"""mcp_stdio_client.py REPO -- COMMAND...: a plain MCP client (JSON-RPC 2.0 over stdio, no dependencies) that
talks to the MCP server started by COMMAND, the way any agent on the host does, e.g.

    python3 mcp_stdio_client.py "$PWD/demo-proof" -- docker exec -i quickproof rocq-mcp

REPO is a built QuickProof proving repository (qpdemo build) with a proof file in src/proof/ (its first file
there; a `Definition *_spec` and a `Lemma body_*`), at a path that is the same on the host and in the container.
The steps: initialize, tools/list, rocq_health, rocq_toc and rocq_compile_file (keep_vo) on that file, an
interactive session on its body lemma (rocq_start, rocq_check of the first tactics, rocq_step_multi), a search
(rocq_query), and the error report of a copy with a false lemma appended.  Prints one line per step; exit 0 when every step gives what it should."""
import json
import os
import re
import subprocess
import sys
import time

if '--' not in sys.argv or len(sys.argv) < 4:
    sys.exit(__doc__)
REPO = os.path.abspath(sys.argv[1])
CMD = sys.argv[sys.argv.index('--') + 1:]
PROOF_DIR = os.path.join(REPO, 'src', 'proof')
FIND = os.path.join(PROOF_DIR, sorted(f for f in os.listdir(PROOF_DIR) if f.endswith('.v'))[0])
_text = open(FIND).read()
BODY = re.search(r'^Lemma (body_\w+)', _text, re.M).group(1)
SPEC = re.search(r'^Definition (\w+_spec)', _text, re.M).group(1)


class Client:
    def __init__(self, cmd):
        self.p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                  text=True, bufsize=1)
        self.n = 0

    def send(self, msg):
        self.p.stdin.write(json.dumps(msg) + '\n')
        self.p.stdin.flush()

    def request(self, method, params=None):
        self.n += 1
        self.send({'jsonrpc': '2.0', 'id': self.n, 'method': method, 'params': params or {}})
        for line in self.p.stdout:
            msg = json.loads(line)
            if msg.get('id') == self.n:
                if 'error' in msg:
                    raise RuntimeError('%s: %s' % (method, msg['error']))
                return msg['result']
        raise RuntimeError('%s: the server closed its output' % method)

    def notify(self, method, params=None):
        self.send({'jsonrpc': '2.0', 'method': method, 'params': params or {}})

    def call(self, tool, **args):
        r = self.request('tools/call', {'name': tool, 'arguments': args})
        if r.get('structuredContent') is not None:
            d = r['structuredContent']
            return d.get('result', d) if isinstance(d, dict) and set(d) == {'result'} else d
        text = ''.join(c.get('text', '') for c in r.get('content', []) if c.get('type') == 'text')
        try:
            return json.loads(text)
        except ValueError:
            return {'text': text, 'isError': r.get('isError')}

    def close(self):
        self.p.stdin.close()
        try:
            self.p.wait(timeout=20)
        except subprocess.TimeoutExpired:
            self.p.terminate()


fails = 0


def one_line(s, n=80):
    s = ' '.join(str(s).split())
    return s if len(s) <= n else s[:n - 3] + '...'


def step(label, ok, detail=''):
    global fails
    fails += 0 if ok else 1
    print('%s %-34s %s' % ('ok  ' if ok else 'FAIL', label, detail), flush=True)


def timed(f, *a, **k):
    t = time.time()
    r = f(*a, **k)
    return r, time.time() - t


c = Client(CMD)
r, dt = timed(c.request, 'initialize', {'protocolVersion': '2025-06-18', 'capabilities': {},
                                        'clientInfo': {'name': 'plain-stdio-client', 'version': '1'}})
c.notify('notifications/initialized')
step('initialize', 'serverInfo' in r, '%s %s (%.1f s)' % (r['serverInfo'].get('name'), r['serverInfo'].get('version'), dt))
tools = sorted(t['name'] for t in c.request('tools/list')['tools'])
step('tools/list', {'rocq_start', 'rocq_check', 'rocq_compile_file', 'rocq_query'} <= set(tools), ', '.join(tools))

h, dt = timed(c.call, 'rocq_health')
step('rocq_health', bool(h.get('success', h.get('ok', True))),
     '%s (%.1f s)' % (json.dumps({k: h[k] for k in list(h)[:6]})[:200], dt))

toc, dt = timed(c.call, 'rocq_toc', file=FIND)
names = json.dumps(toc)
step('rocq_toc %s' % os.path.basename(FIND), BODY in names and SPEC in names, '%s, %s (%.1f s)' % (BODY, SPEC, dt))

comp, dt = timed(c.call, 'rocq_compile_file', file=FIND, keep_vo=True)
step('rocq_compile_file keep_vo=true', comp.get('success') is True and os.path.exists(FIND + 'o'), '(%.1f s)' % dt)

st, dt = timed(c.call, 'rocq_start', file=FIND, theorem=BODY)
sid = st.get('state_id')
goal = json.dumps(st.get('goals'))
step('rocq_start ' + BODY, sid is not None and 'semax_body' in goal, 'state %s (%.1f s)' % (sid, dt))

ck, dt = timed(c.call, 'rocq_check', body='start_function. forward.', from_state=sid)
g = json.dumps(ck.get('goals'))
step('rocq_check start_function. forward.', ck.get('state_id') is not None and 'semax' in g,
     'state %s, goal mentions _i: %s (%.1f s)' % (ck.get('state_id'), '_i' in g, dt))

sm, dt = timed(c.call, 'rocq_step_multi', tactics=['entailer!.', 'lia.', 'reflexivity.'], from_state=ck.get('state_id'))
res = sm.get('results') or []
step('rocq_step_multi 3 tactics', len(res) == 3,
     ', '.join('%s:%s' % (x.get('tactic'), 'ok' if x.get('success') else 'no') for x in res) + ' (%.1f s)' % dt)

q, dt = timed(c.call, 'rocq_query', command='Check Int64.ltu.', file=FIND)
step('rocq_query Check Int64.ltu.', 'int64 -> int64 -> bool' in json.dumps(q), one_line(q.get('output', q)) + ' (%.1f s)' % dt)

broken = os.path.join(PROOF_DIR, 'Broken.v')
src = _text.rstrip('\n') + '\n\nLemma broken_on_purpose : 1 + 1 = 3.\nProof. reflexivity. Qed.\n'
open(broken, 'w').write(src)
bad_line = src.count('\n') - 1
try:
    bad, dt = timed(c.call, 'rocq_compile_file', file=broken)
    pos = [p for p in bad.get('error_positions') or [] if not str(p.get('message', '')).startswith('Warning')]
    step('rocq_compile_file broken copy', bad.get('success') is False and any(p.get('line') == bad_line for p in pos),
         'line %s: %s; state capture %s (%.1f s)' % (pos[0].get('line') if pos else '?',
                                                      one_line(pos[0].get('message', '') if pos else bad, 70),
                                                      bad.get('state_capture_status'), dt))
finally:
    os.remove(broken)
c.close()
print('failures: %d' % fails)
sys.exit(1 if fails else 0)
