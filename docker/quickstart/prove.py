#!/usr/bin/env python3
"""qpdemo prove NAME|LAW: Claude Code writes the proof of a QuickProof law, and qp verify judges it.

Claude Code runs headless (`claude -p`, Anthropic's documented non-interactive mode) in the proving repository
NAME-proof, which `qpdemo contract` makes (this runs it when the repository does not exist yet).  Its brief is
the repository's AGENTS.md.  It may only edit files under src/ (and COUNTEREXAMPLE.md, run/), use the MCP server
rocq (rocq-mcp, from this image) and run the qpdemo/Coq build and check commands; every other action is denied
(permission mode dontAsk, no prompts).  After each session the judge runs `qpdemo verify NAME` (qp verify on a
fresh clone).  If it fails and turns remain, the same conversation is resumed with the judge's report.  The run
ends at PASS, when the turn budget (or the dollar budget) is used up, or when the agent stops making progress.

On the host, with --container C (a running QuickProof container, `qpdemo serve`, with the work directory mounted at
the same path), the same loop drives the host's Claude Code: the MCP server is `docker exec -i C rocq-mcp`, and
the commands are `docker exec C qpdemo ...`.  Your user settings, hooks and plugins are not loaded then
(--setting-sources project,local), so that the run gets only the tools listed here.  This file is
docker/quickstart/prove.py of the QuickProof repository; get it from the image with
`docker exec C cat /opt/quickproof/docker/quickstart/prove.py > qp-prove.py`.

The output: a line per action of the agent, the judge's report after each round, and a summary with the turns,
the wall time, the tokens and Claude Code's own cost estimate.  Everything is kept under NAME-proof/run/qpdemo/:
the raw event stream of each session (JSON lines), the judge's reports, and PROVE.md (the summary).
"""
import argparse
import datetime
import glob
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

TTY = sys.stdout.isatty()
B, OK, BAD, DIM, N = (('\033[1m', '\033[32m', '\033[31m', '\033[2m', '\033[0m') if TTY else ('',) * 5)


def say(*a):
    print(*a, flush=True)


def die(msg, code=2):
    print('qpdemo prove: %s' % msg, file=sys.stderr, flush=True)
    sys.exit(code)


def hms(s):
    s = int(s)
    return '%dh%02dm%02ds' % (s // 3600, s // 60 % 60, s % 60) if s >= 3600 else '%dm%02ds' % (s // 60, s % 60)


def one_line(s, n):
    s = ' '.join(str(s).split())
    return s if len(s) <= n else s[:n - 3] + '...'


# ------------------------------------------------------------------------------------------------- the target
def resolve(work, target):
    """(project, [laws] or None for all) from a project name or a law name."""
    if os.path.isdir(os.path.join(work, 'projects', target)):
        return target, None
    hits = sorted(glob.glob(os.path.join(work, 'projects', '*', 'harness', target + '.c')))
    if len(hits) == 1:
        return hits[0].split(os.sep)[-3], [target]
    if len(hits) > 1:
        die('the law %s is in several projects: %s; name the project' % (target, ', '.join(h.split(os.sep)[-3] for h in hits)))
    die('no project or law %s in %s (qpdemo new NAME makes a project)' % (target, work))


def contract_theorems(repo):
    out = []
    for f in sorted(glob.glob(os.path.join(repo, 'src', 'contracts', '*.v'))):
        out += re.findall(r'^Theorem\s+(\w+)\s*:\s*harness_safe\b', open(f).read(), re.M)
    return out


def src_state(repo):
    """A fingerprint of the files under src/ (to see whether a session changed anything)."""
    r = subprocess.run(['git', '-C', repo, 'status', '--porcelain', '--', 'src'], capture_output=True, text=True)
    h = subprocess.run(['git', '-C', repo, 'rev-parse', 'HEAD'], capture_output=True, text=True)
    files = []
    for d, _, fs in os.walk(os.path.join(repo, 'src')):
        for f in fs:
            if f.endswith('.v'):
                p = os.path.join(d, f)
                files.append((p, os.path.getmtime(p), os.path.getsize(p)))
    return (h.stdout, r.stdout, tuple(sorted(files)))


# ------------------------------------------------------------------------------------------------- the stream
def summarize_tool(name, inp):
    name = name.replace('mcp__rocq__', 'rocq:')
    if not isinstance(inp, dict):
        return name
    if 'file_path' in inp:
        return '%s %s' % (name, inp['file_path'])
    if 'command' in inp:
        return '%s $ %s' % (name, one_line(inp['command'], 110))
    if 'body' in inp:
        return '%s %s' % (name, one_line(inp['body'], 110))
    if 'tactics' in inp:
        return '%s %s' % (name, one_line(' | '.join(inp['tactics']), 110))
    keys = [k for k in ('theorem', 'file', 'name', 'pattern', 'path') if inp.get(k)]
    return '%s %s' % (name, ' '.join('%s=%s' % (k, one_line(inp[k], 70)) for k in keys)) if keys else name


def run_session(cmd, env, cwd, log_path, t_start):
    """Runs one Claude Code session, renders its stream-json events, keeps them in log_path.  Returns
    (result event or None, init event or None, exit status, stats).  stats: `turns`, the tool-use round trips
    (model responses that call tools; what --max-turns counts, several parallel calls being one), and
    `tool_calls`.  (Claude Code's own `num_turns` in the result counts otherwise: about one per tool call.)"""
    result, init = None, None
    turn_ids, anon_turns, tool_calls = set(), 0, 0
    with open(log_path, 'a') as log:
        p = subprocess.Popen(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                             bufsize=1, start_new_session=True)
        try:
            for line in p.stdout:
                log.write(line)
                log.flush()
                stamp = '%s[%s]%s' % (DIM, hms(time.time() - t_start), N)
                try:
                    ev = json.loads(line)
                except ValueError:
                    if line.strip():
                        say('%s %s' % (stamp, one_line(line, 150)))
                    continue
                typ = ev.get('type')
                if typ == 'system' and ev.get('subtype') == 'init':
                    init = ev
                    servers = ', '.join('%s: %s' % (s.get('name'), s.get('status')) for s in ev.get('mcp_servers') or [])
                    say('%s session %s, model %s; MCP %s' % (stamp, (ev.get('session_id') or '')[:8], ev.get('model'),
                                                             servers or 'none'))
                elif typ == 'system' and ev.get('subtype') == 'api_retry':
                    say('%s API retry %s/%s (%s)' % (stamp, ev.get('attempt'), ev.get('max_retries'), ev.get('error')))
                elif typ == 'assistant':
                    msg = ev.get('message') or {}
                    if any(c.get('type') == 'tool_use' for c in msg.get('content') or []):
                        if msg.get('id'):
                            turn_ids.add(msg['id'])
                        else:
                            anon_turns += 1
                    for c in msg.get('content') or []:
                        if c.get('type') == 'text' and c.get('text', '').strip():
                            say('%s %s> %s%s' % (stamp, B, one_line(c['text'], 160), N))
                        elif c.get('type') == 'tool_use':
                            tool_calls += 1
                            say('%s   %s' % (stamp, summarize_tool(c.get('name', '?'), c.get('input'))))
                elif typ == 'user':
                    for c in (ev.get('message') or {}).get('content') or []:
                        if isinstance(c, dict) and c.get('type') == 'tool_result' and c.get('is_error'):
                            body = c.get('content')
                            if isinstance(body, list):
                                body = ' '.join(x.get('text', '') for x in body if isinstance(x, dict))
                            say('%s     %s! %s%s' % (stamp, BAD, one_line(body, 140), N))
                elif typ == 'result':
                    result = ev
        except KeyboardInterrupt:
            os.killpg(p.pid, signal.SIGINT)
            try:
                p.wait(timeout=30)
            except subprocess.TimeoutExpired:
                os.killpg(p.pid, signal.SIGTERM)
            raise
        rc = p.wait()
    return result, init, rc, {'turns': len(turn_ids) + anon_turns, 'tool_calls': tool_calls}


# ------------------------------------------------------------------------------------------------- the judge
QPDEMO = ['qpdemo']   # in the container; on the host: ['docker', 'exec', C, 'qpdemo']


def judge(name, laws, repo, log_path):
    """qpdemo verify NAME; returns (passed, report text).  For one law of a project with several, the law passes
    when its row is PROVED, no frozen file changed and every statement is the contract's."""
    r = subprocess.run(QPDEMO + ['verify', name], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    text = r.stdout   # qp verify's progress (stderr) and its report (stdout), in the order they came
    open(log_path, 'w').write(text)
    if r.returncode == 0:
        return True, text
    if laws:
        rows = dict(re.findall(r'^\| `(\w+)` \| ([A-Z][^|]*?) \|', text, re.M))
        clean = ('frozen files changed: none' in text and '**DIFFERENT' not in text
                 and 'regenerated code.v: identical' in text)
        return clean and all(rows.get(l, '').startswith('PROVED') for l in laws), text
    return False, text


def report_excerpt(text, n=40):
    m = text.find('# Verification')
    lines = (text[m:] if m >= 0 else text).strip().splitlines()
    return '\n'.join(lines[:n] if m >= 0 else lines[-n:])


# ------------------------------------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(
        prog='qpdemo prove',
        description='Claude Code writes the proof of a law of your project; qp verify judges it.  Needs '
                    '`qpdemo agent setup` and a login (qpdemo agent login), or -e ANTHROPIC_API_KEY, or '
                    '-e CLAUDE_CODE_OAUTH_TOKEN.  Costs API money or subscription usage; success is not guaranteed.')
    ap.add_argument('target', help='a project NAME (prove all its laws) or one LAW (a harness name)')
    ap.add_argument('--budget-turns', type=int, default=100, metavar='N',
                    help='agent turns in all, over all rounds (default 100)')
    ap.add_argument('--model', metavar='M', help="Claude Code's --model (an alias such as opus or sonnet, or a full name)")
    ap.add_argument('--effort', metavar='E', help="Claude Code's --effort (low, medium, high, xhigh, max)")
    ap.add_argument('--budget-usd', type=float, metavar='X',
                    help="stop when Claude Code's own cost estimate reaches X dollars (its --max-budget-usd)")
    ap.add_argument('--rounds', type=int, default=6, metavar='R', help='at most R sessions (default 6)')
    ap.add_argument('--container', metavar='C', help='run on the host, with the QuickProof container C (qpdemo serve) '
                    'for the MCP server and the commands; the work directory must be mounted at the same path')
    ap.add_argument('--work', default=os.environ.get('QP_WORK', '/work'),
                    help='the work directory (in the container: $QP_WORK; on the host: give it)')
    a = ap.parse_args()
    global QPDEMO
    if a.container:
        QPDEMO = ['docker', 'exec', a.container, 'qpdemo']
    qd = ' '.join(QPDEMO)

    claude = shutil.which('claude')
    if not claude:
        die('Claude Code is not installed: qpdemo agent setup')
    work = os.path.realpath(a.work)
    name, laws = resolve(work, a.target)
    repo = os.path.join(work, name + '-proof')
    if not os.path.isdir(os.path.join(repo, '.git')):
        say('%s== no proving repository yet: qpdemo contract %s%s' % (B, name, N))
        if subprocess.run(QPDEMO + ['contract', name]).returncode != 0:
            die('qpdemo contract %s failed' % name)
    thms = contract_theorems(repo)
    what = ('the theorem `%s` (the law harness/%s.c)' % (laws[0], laws[0]) if laws and len(thms) > 1 else
            'the theorem%s %s' % ('s' if len(thms) > 1 else '', ', '.join('`%s`' % t for t in thms)))

    # credentials: an environment variable, or a login kept by Claude Code
    if not (os.environ.get('ANTHROPIC_API_KEY') or os.environ.get('CLAUDE_CODE_OAUTH_TOKEN')):
        st = subprocess.run([claude, 'auth', 'status'], capture_output=True, text=True)
        if st.returncode != 0:
            die('Claude Code is not signed in: run qpdemo agent login (docker run -it ...), or pass '
                '-e ANTHROPIC_API_KEY or -e CLAUDE_CODE_OAUTH_TOKEN')

    rundir = os.path.join(repo, 'run', 'qpdemo')
    os.makedirs(rundir, exist_ok=True)
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    mcp_path = os.path.join(tempfile.mkdtemp(prefix='qpdemo-mcp-'), 'mcp.json')
    server = ({'type': 'stdio', 'command': 'docker', 'args': ['exec', '-i', '-e', 'ROCQ_WORKSPACE=' + repo, a.container,
                                                              'rocq-mcp']} if a.container else
              {'type': 'stdio', 'command': 'rocq-mcp', 'args': [], 'env': {'ROCQ_WORKSPACE': repo}})
    json.dump({'mcpServers': {'rocq': server}}, open(mcp_path, 'w'), indent=1)
    allowed = ['Edit(/src/**)', 'Edit(/COUNTEREXAMPLE.md)', 'Edit(/run/**)', 'mcp__rocq',
               'Bash(%s build *)' % qd, 'Bash(%s verify *)' % qd, 'Bash(%s check *)' % qd, 'Bash(%s show *)' % qd]
    if not a.container:
        allowed += ['Bash(make -f CoqMakefile *)', 'Bash(coq_makefile *)', 'Bash(coqc *)', 'Bash(qp verify *)']
    base = [claude, '-p', None, '--output-format', 'stream-json', '--verbose',
            '--permission-mode', 'dontAsk', '--permission-prompts', 'none',
            '--allowedTools', ','.join(allowed),
            '--mcp-config', mcp_path, '--strict-mcp-config']
    # The sources of Coq's libraries, VST's among them, for the agent to read (dontAsk denies edits there).
    coqlib = '' if a.container else subprocess.run(['coqc', '-where'], capture_output=True, text=True).stdout.strip()
    for d in ([] if a.container else [os.path.join(coqlib, 'user-contrib'), '/tmp']):
        if os.path.isdir(d):
            base += ['--add-dir', d]
    if a.container:
        base += ['--setting-sources', 'project,local']
    if a.model:
        base += ['--model', a.model]
    if a.effort:
        base += ['--effort', a.effort]
    env = dict(os.environ, BASH_DEFAULT_TIMEOUT_MS='900000', BASH_MAX_TIMEOUT_MS='1800000', MCP_TIMEOUT='120000')

    first = ("Prove {what} of this repository ({repo}).\n\n"
             "AGENTS.md in this directory is your brief: read it first and follow it. In short: write VST "
             "specifications and proofs under src/; never change a theorem's statement or any frozen file; never use "
             "Admitted, admit or axioms. Use the MCP server `rocq` for goals and tactic steps, `{qd} build {name}` to "
             "compile, and the worked examples it names as patterns.{host}\n\n"
             "You are done only when `{qd} verify {name}` prints PASS. If the law turns out to be false, write the "
             "counterexample into COUNTEREXAMPLE.md and stop. You run unattended: nobody can answer questions, so "
             "do not ask any; keep working until it passes.").format(
                 what=what, repo=repo, name=name, qd=qd,
                 host=(' You run on the host; the Coq toolchain is in the container {c}: run the qpdemo commands as '
                       '`{qd} ...` (exactly so: other commands are not allowed), and the MCP server works on the '
                       'same paths as you.'.format(c=a.container, qd=qd) if a.container else ''))

    say('%s== qpdemo prove %s%s: Claude Code (%s) writes the proof, qp verify judges' % (B, a.target, N, claude))
    say('repository %s; budget %d turns%s, at most %d rounds' % (
        repo, a.budget_turns, ', $%.2f' % a.budget_usd if a.budget_usd else '', a.rounds))
    say('allowed: edits under src/, the MCP server rocq, %s build/verify/check/show%s; nothing else'
        % (qd, '' if a.container else ', make/coqc'))
    t0 = time.time()
    turns, calls, cc_turns, cost, usage, model, session, rounds, verdict, why = 0, 0, 0, 0.0, {}, None, None, [], False, ''
    prompt = first
    try:
        for rnd in range(1, a.rounds + 1):
            left = a.budget_turns - turns
            if left <= 0:
                why = 'the turn budget (%d) is used up' % a.budget_turns
                break
            if a.budget_usd and cost >= a.budget_usd:
                why = 'the dollar budget ($%.2f) is used up' % a.budget_usd
                break
            cmd = list(base)
            cmd[2] = prompt
            cmd += ['--max-turns', str(left)]
            if a.budget_usd:
                cmd += ['--max-budget-usd', '%.2f' % (a.budget_usd - cost)]
            if session:
                cmd += ['--resume', session]
            say('\n%s== round %d: %s, up to %d turns%s' % (B, rnd, 'new session' if not session else 'resumed', left, N))
            before = src_state(repo)
            log = os.path.join(rundir, '%s-round%d.jsonl' % (stamp, rnd))
            res, init, rc, stats = run_session(cmd, env, repo, log, t0)
            if init:
                model = model or init.get('model')
                session = session or init.get('session_id')
            n = stats['turns']
            calls += stats['tool_calls']
            if res:
                cc_turns += int(res.get('num_turns') or 0)
                cost = max(cost, float(res.get('total_cost_usd') or 0))   # Claude Code reports the conversation's total
                for k, v in (res.get('usage') or {}).items():
                    if isinstance(v, (int, float)):
                        usage[k] = usage.get(k, 0) + v
                session = res.get('session_id') or session
            turns += n
            changed = src_state(repo) != before
            sub = res.get('subtype') if res else 'no result (exit %d)' % rc
            say('%s-- round %d ended: %s, %d turns (total %d of %d), cost so far $%.2f (Claude Code\'s estimate)%s'
                % (B, rnd, sub, n, turns, a.budget_turns, cost, N))
            if res and res.get('is_error') and sub not in ('error_max_turns', 'error_max_budget_usd', 'success'):
                rounds.append((rnd, n, sub, None))
                why = 'Claude Code stopped with an error: %s' % one_line(res.get('result') or sub, 300)
                break
            if not res:
                rounds.append((rnd, n, sub, None))
                why = 'Claude Code ended without a result (exit %d; see %s)' % (rc, log)
                break
            say('\n%s== the judge: %s verify %s%s' % (B, qd, name, N))
            verdict, text = judge(name, laws, repo, os.path.join(rundir, '%s-verify%d.log' % (stamp, rnd)))
            say(report_excerpt(text, 30))
            rounds.append((rnd, n, sub, verdict))
            if verdict:
                why = 'qp verify passed'
                break
            if os.path.exists(os.path.join(repo, 'COUNTEREXAMPLE.md')):
                why = 'the agent reports a counterexample (COUNTEREXAMPLE.md): check it, e.g. with qpdemo check'
                break
            if not changed and n <= 2:
                why = 'the agent stopped without changing anything'
                break
            if sub == 'error_max_budget_usd':
                why = 'the dollar budget is used up'
                break
            prompt = ("The judge ran `{qd} verify {name}` after your session, and it did not pass. Its report:\n\n"
                      "{rep}\n\nContinue from where you are: fix what it reports and keep working until "
                      "`{qd} verify {name}` prints PASS. Follow AGENTS.md.").format(qd=qd, name=name, rep=report_excerpt(text))
        else:
            why = why or 'the round limit (%d) is reached' % a.rounds
    except KeyboardInterrupt:
        why = 'interrupted'
    wall = time.time() - t0
    if not why:
        why = 'the turn budget (%d) is used up' % a.budget_turns

    tok = ', '.join('%s %d' % (k, usage[k]) for k in ('input_tokens', 'cache_creation_input_tokens',
                                                     'cache_read_input_tokens', 'output_tokens') if k in usage)
    lines = ['# qpdemo prove %s' % a.target, '',
             '- date: %s' % datetime.datetime.now().strftime('%Y-%m-%d %H:%M'),
             '- repository: %s' % repo,
             '- agent: Claude Code %s, model %s' % (subprocess.run([claude, '--version'], capture_output=True,
                                                                   text=True).stdout.strip(), model),
             '- budget: %d turns%s' % (a.budget_turns, ', $%.2f' % a.budget_usd if a.budget_usd else ''),
             '- rounds: %d (%s)' % (len(rounds), '; '.join('%d: %d turns, %s, judge %s' % (r, n, s, {True: 'PASS', False: 'FAIL', None: 'not run'}[v])
                                                         for r, n, s, v in rounds)),
             '- turns: %d tool-use round trips (what --max-turns counts); %d tool calls; Claude Code\'s num_turns %d'
             % (turns, calls, cc_turns),
             '- wall time: %s' % hms(wall),
             '- tokens (as Claude Code reports them, summed over the rounds): %s' % (tok or 'none reported'),
             "- cost: $%.2f (Claude Code's client-side estimate at API prices; on a subscription it is usage, not a bill)" % cost,
             '- outcome: %s, because %s' % ('PASS' if verdict else 'not proved', why),
             '- logs: %s/%s-*' % (rundir, stamp)]
    open(os.path.join(rundir, 'PROVE.md'), 'a').write('\n'.join(lines) + '\n\n')
    say('\n%s== summary%s' % (B, N))
    say('\n'.join(lines[2:]))
    say('')
    if verdict:
        say('%s%sPASS%s %s: proved by the agent, accepted by qp verify. The proof is in %s/src (committed).'
            % (OK, B, N, a.target, repo))
    else:
        say('%s%sNOT PROVED%s %s: %s. The work so far is in %s; run qpdemo prove %s again to continue in a new '
            'session, or take over by hand.' % (BAD, B, N, a.target, why, repo, a.target))
    sys.exit(0 if verdict else 1)


if __name__ == '__main__':
    main()
