#
# The QuickProof image: check the shipped proofs, and prove laws of your own C code (docs/DOCKER.md).
#
# It holds the toolchain image (docker/toolchain.Dockerfile, target toolchain: Coq 8.20.1, CompCert 3.15,
# VST 2.15, coq-lsp), this repository in /opt/quickproof, the examples assembled into proof repositories in
# /opt/qp-examples, the MCP server rocq-mcp, and the entry point qpdemo (docker/quickstart/qpdemo).  No AI agent
# is included: `qpdemo agent setup` installs Claude Code at run time, with Anthropic's installer, when the user
# asks for it.
#
# docker/build.sh builds it.  It puts the commit checked out into the build context as a git repository of that
# one commit, with the same hash, and this file copies that repository to /opt/quickproof.  qp needs a real git
# repository there: the projects made in the image pin its commit, and qp verify takes the framework from it.
#
#   docker/build.sh                                 quickproof:latest, on quickproof-toolchain:8.20.1
#   docker run --rm quickproof:latest               the list of commands
#   docker run --rm quickproof:latest verify rle    check a shipped proof from scratch
ARG TOOLCHAIN=quickproof-toolchain:8.20.1

FROM ${TOOLCHAIN}
ARG JOBS=4
ARG REVISION=
LABEL org.opencontainers.image.source=https://github.com/genproof/quickproof-public \
      org.opencontainers.image.revision=${REVISION} \
      org.opencontainers.image.description="QuickProof: check proofs of C code, and prove laws of your own"
USER root
# nano: an editor for proving by hand; curl: Anthropic's installer (qpdemo agent setup); python3-venv: rocq-mcp.
# For containers run with --user: the toolchain in /home/opam is readable by every user id (useradd on Ubuntu
# 24.04 makes home directories 750), and the cache directory writable.
RUN apt-get update \
 && apt-get install -y --no-install-recommends nano curl python3-venv \
 && rm -rf /var/lib/apt/lists/* \
 && chmod 755 /home/opam \
 && mkdir -p /opt/qp-examples /work /home/opam/.local/bin /home/opam/.cache \
 && chown opam:opam /opt/qp-examples /work /home/opam/.local /home/opam/.local/bin /home/opam/.cache \
 && chmod 1777 /home/opam/.cache
# The MCP server rocq-mcp (github.com/LLM4Rocq/rocq-mcp, Apache-2.0): goals, tactic steps, searches and compiles
# for an agent, through the `pet` server of coq-lsp.  Pinned with all its dependencies.
COPY quickproof/docker/quickstart/rocq-mcp-requirements.txt /tmp/rocq-mcp-requirements.txt
RUN python3 -m venv /opt/rocq-mcp \
 && /opt/rocq-mcp/bin/pip install --no-cache-dir -q -r /tmp/rocq-mcp-requirements.txt \
 && ln -s /opt/rocq-mcp/bin/rocq-mcp /usr/local/bin/rocq-mcp \
 && mkdir -p /usr/share/doc/quickproof-toolchain \
 && cp /opt/rocq-mcp/lib/python3*/site-packages/rocq_mcp-*.dist-info/licenses/LICENSE \
       /usr/share/doc/quickproof-toolchain/rocq-mcp-LICENSE \
 && rm /tmp/rocq-mcp-requirements.txt
# git for every user id, since a container may run as the host's: local clones as file:// URLs (a plain local
# clone hard-links objects, which git refuses for the files of a lower layer of an overlay file system), an
# identity for the commits qpdemo makes, and no ownership check on the repositories of the image and of /work.
RUN git config --system url."file:///".insteadOf / \
 && git config --system user.name "QuickProof user" \
 && git config --system user.email "user@quickproof.invalid" \
 && git config --system safe.directory '*' \
 && git config --system init.defaultBranch main
# QuickProof (PolyForm Noncommercial License 1.0.0): this repository at the commit docker/build.sh took.
COPY --chown=opam:opam quickproof /opt/quickproof
RUN ln -s /opt/quickproof/docker/quickstart/qpdemo /usr/local/bin/qpdemo
USER opam
# CLAUDE_CONFIG_DIR: Claude Code's settings, login and MCP registration go next to its program in ~/.local, so
# that one volume on /home/opam/.local keeps all of it (qpdemo agent setup).  ROCQ_COQC_TIMEOUT: rocq-mcp's limit
# on a compile; its default, 60 seconds, is short for a VST proof file.
ENV PATH=/opt/quickproof/tools:/home/opam/.local/bin:/home/opam/.opam/4.14/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    QP_CACHE=/home/opam/.cache/quickproof \
    QP_SITE_CONF=/dev/null \
    GIT_TERMINAL_PROMPT=0 \
    CLAUDE_CONFIG_DIR=/home/opam/.local/claude \
    ROCQ_COQC_TIMEOUT=600
RUN cd /opt/quickproof/coq \
 && coq_makefile -f _CoqProject -o Makefile.coq > /dev/null \
 && { make -s -f Makefile.coq -j"$JOBS" > /tmp/coq.log 2>&1 || { tail -40 /tmp/coq.log; exit 1; }; } \
 && rm /tmp/coq.log
# The examples (examples/) as proof repositories, and the bug scene: make-examples.sh.
RUN bash /opt/quickproof/docker/quickstart/make-examples.sh \
 && rm -rf /home/opam/.cache/quickproof/trees
WORKDIR /work
ENTRYPOINT ["/usr/local/bin/qpdemo"]
CMD ["help"]
