# QuickProof in Docker

The image `ghcr.io/genproof/quickproof` has everything QuickProof needs to check a proof and to make one. Its entry
point, `qpdemo`, wraps `tools/qp` and lists its commands when run without arguments. The image runs on 64-bit x86,
and on Apple Silicon under Rosetta, more slowly (in Docker Desktop, turn on "Use Rosetta for x86_64/amd64 emulation
on Apple Silicon"; OrbStack does this by default).

## What the image contains

The image holds Ubuntu 24.04 with GCC 13 and its sanitizers; the toolchain image `docker/toolchain.Dockerfile` (Coq
8.20.1, CompCert 3.15 and VST 2.15 built with opam, coq-lsp 0.2.5 with its `pet` server, and CoqHammer's
reconstruction tactics); QuickProof in `/opt/quickproof`, with `qp` in the `PATH`; the three
[examples](../examples/README.md) with their proofs in `/opt/qp-examples`; and the MCP server
[rocq-mcp](https://github.com/LLM4Rocq/rocq-mcp), pinned in `docker/quickstart/rocq-mcp-requirements.txt`. No AI
agent is included.

QuickProof is under the PolyForm Noncommercial License 1.0.0, Coq under the LGPL 2.1, VST under a BSD licence and
rocq-mcp under the Apache License 2.0. CompCert is under the INRIA Non-Commercial License, which allows educational,
research and evaluation use only; commercial use needs a licence from AbsInt. The licence texts are in
`/opt/quickproof/LICENSE` and `/usr/share/doc/quickproof-toolchain`.

## Check a proof

```sh
docker run --rm ghcr.io/genproof/quickproof verify rle
```

This checks the proof of the example `rle`, a run-length decoder, with `qp verify`, offline, and prints `PASS`
after about a minute.

```sh
docker run --rm ghcr.io/genproof/quickproof list         # the examples and their properties
docker run --rm ghcr.io/genproof/quickproof show rle     # the spec, the code and the theorem
docker run --rm ghcr.io/genproof/quickproof verify all   # rle, adler32 and find_byte
docker run --rm ghcr.io/genproof/quickproof bug
```

`bug` shows a false property: version 2.0 of the decoder reads one byte past an input of odd length, and the
spec of `rle`, run natively under AddressSanitizer, finds such an input in a few seconds.

## Prove a property of your own code

The property is stated by a spec, a C program you can run that calls your code on arbitrary input and checks the
result with `qp_assert`. Mount a directory on `/work` to keep your work:

```sh
mkdir qp && cd qp
alias qpdemo='docker run -it --rm -v "$PWD:/work" ghcr.io/genproof/quickproof'
qpdemo new mylib          # mylib-src/: your code; projects/mylib/harness/: the spec
# replace the example function in mylib-src/ and the spec in projects/mylib/harness/ by your own
qpdemo check mylib        # native runs, CompCert's interpreter, mutants of your code
qpdemo contract mylib     # mylib-proof/: the theorem to prove
qpdemo build mylib        # compile the proof; lists what is still Admitted
qpdemo verify mylib       # the acceptance check
```

`new` starts from the function `count_byte` and its spec `count_byte_ok`. `contract` writes the theorem,
unproved, at the end of `mylib-proof/src/contracts/count_byte_ok.v` and commits the repository under the tag
`contract`. It also writes `AGENTS.md`, the brief for whoever writes the proof. The worked examples are in
`mylib-proof/quickproof/examples/`. The proof is done when `qpdemo verify mylib`, which commits your changes under
`src/`, prints `PASS`.

`build` runs 4 parallel jobs, and `verify` and `check` use half the CPUs; `-e QP_BUILD_JOBS=N` and `-e QP_JOBS=N`
change these.

## Let an AI agent write the proof

Nothing an agent writes is trusted. `qp verify` accepts a proof only when Coq checks it, its statement is the one
generated from your spec before the agent started, nothing is admitted, and only a short fixed list of axioms is
used. The agent runs on your own subscription or API key.

### Claude Code inside the container

`qpdemo agent setup` installs Claude Code into `/home/opam/.local`, where a named volume keeps it installed and
signed in:

```sh
alias qpdemo='docker run -it --rm -v quickproof-agent:/home/opam/.local -v "$PWD:/work" ghcr.io/genproof/quickproof'
qpdemo agent setup        # downloads Claude Code from Anthropic (about 270 MB in the volume)
qpdemo agent login        # once: sign in with your Claude subscription
```

The login prints a URL: open it in a browser on any machine and paste the code it shows at the prompt. Instead you
can pass `-e ANTHROPIC_API_KEY` (a Claude Console key, billed per token) or `-e CLAUDE_CODE_OAUTH_TOKEN` (from
`claude setup-token`, on your subscription), by name so that the value stays off the command line:

```sh
export ANTHROPIC_API_KEY=...
docker run -it --rm -e ANTHROPIC_API_KEY -v quickproof-agent:/home/opam/.local -v "$PWD:/work" \
    ghcr.io/genproof/quickproof prove mylib --budget-turns 80
```

With a login, run `qpdemo prove mylib --budget-turns 80`, which also takes `--model`, `--effort`, `--budget-usd`,
or one spec's name instead of the project. It runs Claude Code without questions (`claude -p`) in `mylib-proof/`
with `AGENTS.md` as its brief. The agent may only edit files under `src/` (and `COUNTEREXAMPLE.md` and `run/`),
use the MCP server `rocq` and run `qpdemo build`, `qpdemo verify`, `qpdemo check`, `make` and `coqc`. After each round `prove` runs `qpdemo verify`
and, while turns remain, resumes with its report. The run ends at `PASS`, at the end of the budget, when the agent
stops without changing anything, or when it finds the property false. In that case it is told to write the
input that breaks the property, and the reason, into `COUNTEREXAMPLE.md` and stop. A turn is one model response
that calls tools. `mylib-proof/run/qpdemo/` keeps the logs and `PROVE.md`, a summary. Run `prove` again to continue
in a new session. For interactive work, run `qpdemo bash`, then `cd mylib-proof` and `claude`.

### An agent on the host

Keep a container running with your directory mounted at the same path inside:

```sh
docker run -d --name quickproof -v "$PWD:$PWD" -e QP_WORK="$PWD" -w "$PWD" ghcr.io/genproof/quickproof serve
claude mcp add rocq -- docker exec -i quickproof rocq-mcp     # Claude Code
codex mcp add rocq -- docker exec -i quickproof rocq-mcp      # Codex CLI
```

The agent edits the files on the host and runs `docker exec quickproof qpdemo build mylib` and
`docker exec quickproof qpdemo verify mylib`. Point it at `mylib-proof/AGENTS.md`. Compiling a proof file can take
minutes, so raise Codex's tool timeout in `~/.codex/config.toml`:

```toml
[mcp_servers.rocq]
command = "docker"
args = ["exec", "-i", "quickproof", "rocq-mcp"]
tool_timeout_sec = 600
```

Cursor (`.cursor/mcp.json`) and most other MCP clients take the server in this shape:

```json
{ "mcpServers": { "rocq": { "type": "stdio", "command": "docker",
                            "args": ["exec", "-i", "quickproof", "rocq-mcp"] } } }
```

The loop of `qpdemo prove` also runs with Claude Code on the host, with the same permissions and without your user
settings, hooks or plugins:

```sh
docker exec quickproof cat /opt/quickproof/docker/quickstart/prove.py > qp-prove.py
python3 qp-prove.py --container quickproof --work "$PWD" mylib --budget-turns 60
```

`docker stop quickproof` ends the container; your files stay.

### By hand in VS Code

Copy `docker/devcontainer/devcontainer.json` into `.devcontainer/` of your directory and run "Dev Containers:
Reopen in Container", or use GitHub Codespaces. Run `qpdemo build mylib` once, then open the proof repository as a
folder of its own (File > Open Folder > `/work/mylib-proof`). coq-lsp reads `_CoqProject` at the root of the
folder; with `/work` open it finds none and reports every `Require` as an error. Version 0.80 of the Dev
Containers CLI hangs with Docker Engine 29; 0.89 works.

## What to expect

We ran this setup for four properties that had no proof yet. The agent had the brief and the worked examples, nothing
else, and each run ended with `PASS` in its first session.

| property | way | turns |
|---|---|---|
| `count_byte_ok`, the spec of `qpdemo new` | Claude Code in the container | 53 |
| `max_byte_ok`: no byte exceeds the result of `max_byte` | Claude Code on the host | 36 |
| `copy_upto_ok`: copies a prefix, and stops early only at `c` | Claude Code in the container | 71 |
| `rstrip_ok`: only spaces after the result, and no space just before it | Claude Code in the container | 51 |

Each proof is 180 to 270 lines of Coq for a function of ten lines with one loop. A function with several loops,
pointer arithmetic or a data structure needs a much longer proof. An agent can also get stuck on a loop invariant
or run out of budget.

## Volumes and users

In `/work`, `NAME-src/` is a git repository in which `qpdemo` commits your edits.
Claude Code updates itself in the volume `quickproof-agent`, and `docker volume rm quickproof-agent` removes it and
its login; the rest is rebuilt in each container.

The image's user is `opam`, user id 1000. If your user id on a Linux host differs, add `--user "$(id -u):$(id -g)"`
to every `docker run` so that the files in `/work` are yours. With another user id, `qpdemo` keeps its cache in
`/tmp`. Claude Code inside the container needs the image's own user, so with another user id run your agent on
the host.

## Limits

- CompCert configured for ARM gives a different C semantics (`char` is unsigned there), so a proof made on x86
  would not match on ARM.
- Larger proofs take longer. `qp verify` took 17 minutes for OpenSSL's punycode decoder and about 8 hours for
  zlib and about 7 hours for zstd's decoder with 8 build jobs, and about 19 hours for WireGuard with 4, on 16 CPUs.
- `qpdemo prove` and `qpdemo agent setup` need the network.
- The image has no clang, so `qp fidelity`, `qp fuzz --libfuzzer` and `qp import-cbmc` do not run in it.
- In rocq-mcp, `rocq_compile_file` deletes the `.vo` it produces unless given `keep_vo=true`, so the files that
  import it need `qpdemo build` again. `rocq_assumptions` gives no useful list for VST proofs; `qp verify` prints
  the real `Print Assumptions`.
- A Coq build can run code that the repository brings along, so check proofs from people you do not trust in the
  container.

## Building the image

```sh
docker/build.sh              # quickproof:latest, on the toolchain image quickproof-toolchain:8.20.1
docker/build.sh toolchain    # builds the toolchain image first, from docker/toolchain.Dockerfile
```

`docker/build.sh` builds `docker/quickstart.Dockerfile` from the commit checked out, not from the working tree. The
image keeps that commit as `/opt/quickproof`, and its projects pin it. Build an image for other people from a
commit the public repository has. The toolchain image takes 40 to 60 minutes at 4 jobs, the image on top of it
about two minutes. `QP_TOOLCHAIN_IMAGE=ghcr.io/genproof/quickproof-toolchain:8.20.1` builds on the published
toolchain image, and `QP_IMAGE` sets the tag. With a local build, use its tag, `quickproof:latest`, in place of
`ghcr.io/genproof/quickproof` in the commands on this page.

`docker/tests/` tests an image without a real agent: `prove_fake.sh` (with a fake `claude`), `host_agent_test.sh`,
`devcontainer_test.sh`, `asan_check.sh` and `measure.sh`.
