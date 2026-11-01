#!/usr/bin/env python3
"""lsp_check.py ROOT FILE [EXPECT] -- COMMAND...: opens FILE in the language server started by COMMAND (coq-lsp,
e.g. `docker exec -i CONTAINER coq-lsp`), the way the VS Code extension does: initialize with the workspace
folder ROOT, didOpen, then the diagnostics coq-lsp publishes once it has checked the whole file.  Paths are the
container's.  EXPECT: `clean` (default: no error), `error:LINE` (an error on that line, 1-based), or `errors`
(at least one error).
Prints the errors and the time taken; exit 0 when the result is as expected."""
import json
import os
import subprocess
import sys
import threading
import time
import queue

if '--' not in sys.argv:
    sys.exit(__doc__)
k = sys.argv.index('--')
ROOT, FILE = sys.argv[1], sys.argv[2]
EXPECT = sys.argv[3] if k > 3 else 'clean'
CMD = sys.argv[k + 1:]
TEXT = open(FILE).read() if os.path.exists(FILE) else subprocess.run(
    CMD[:CMD.index('-i')] + [CMD[CMD.index('-i') + 1], 'cat', FILE], capture_output=True, text=True).stdout


def uri(p):
    return 'file://' + p


p = subprocess.Popen(CMD, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
inbox = queue.Queue()


def reader():
    while True:
        head = {}
        while True:
            line = p.stdout.readline()
            if not line:
                inbox.put(None)
                return
            line = line.decode().strip()
            if not line:
                break
            key, _, val = line.partition(':')
            head[key.lower()] = val.strip()
        inbox.put(json.loads(p.stdout.read(int(head['content-length']))))


threading.Thread(target=reader, daemon=True).start()


def send(msg):
    body = json.dumps(msg).encode()
    p.stdin.write(b'Content-Length: %d\r\n\r\n' % len(body) + body)
    p.stdin.flush()


t0 = time.time()
send({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {
    'processId': None, 'rootUri': uri(ROOT), 'workspaceFolders': [{'uri': uri(ROOT), 'name': os.path.basename(ROOT)}],
    'capabilities': {'textDocument': {'publishDiagnostics': {}}}, 'initializationOptions': {}}})
server = None
while server is None:
    m = inbox.get(timeout=120)
    if m and m.get('id') == 1:
        server = m['result'].get('serverInfo', {})
send({'jsonrpc': '2.0', 'method': 'initialized', 'params': {}})
send({'jsonrpc': '2.0', 'method': 'textDocument/didOpen', 'params': {'textDocument': {
    'uri': uri(FILE), 'languageId': 'coq', 'version': 1, 'text': TEXT}}})
diags, done, last = None, False, time.time()
nlines = TEXT.count('\n') + 1
while time.time() - t0 < 900:
    try:
        m = inbox.get(timeout=5)
    except queue.Empty:
        if diags is not None and time.time() - last > 10:
            break
        continue
    if m is None:
        break
    if m.get('method') == 'textDocument/publishDiagnostics' and m['params']['uri'] == uri(FILE):
        diags, last = m['params']['diagnostics'], time.time()
    elif m.get('method') == '$/coq/fileProgress':
        last = time.time()
    elif m.get('method') == '$/coq/filePerfData' or (m.get('method') or '').endswith('fileDone'):
        done = True
        last = time.time()
    if 'id' in m and 'method' in m:   # a request from the server: answer it
        send({'jsonrpc': '2.0', 'id': m['id'], 'result': None})
dt = time.time() - t0
errors = [d for d in (diags or []) if d.get('severity') == 1]
print('server: %s %s; %s: %d diagnostics, %d errors (%.1f s)' % (
    server.get('name'), server.get('version'), os.path.relpath(FILE, ROOT), len(diags or []), len(errors), dt))
for d in errors[:5]:
    print('  error line %d: %s' % (d['range']['start']['line'] + 1, ' '.join(d['message'].split())[:150]))
p.terminate()
if diags is None:
    print('FAIL: no diagnostics')
    sys.exit(1)
if EXPECT == 'clean':
    ok = not errors
elif EXPECT == 'errors':
    ok = bool(errors)
else:
    want = int(EXPECT.split(':')[1])
    ok = any(d['range']['start']['line'] + 1 == want for d in errors)
print('ok' if ok else 'FAIL (expected %s)' % EXPECT)
sys.exit(0 if ok else 1)
