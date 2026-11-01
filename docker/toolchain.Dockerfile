#
# The QuickProof toolchain image: Coq 8.20.1, CompCert 3.15 and VST 2.15, with coq-lsp and CoqHammer's tactics,
# all from opam.  Public components only.  Slow to build (40 to 60 minutes at -j4, longer on CI runners) and
# rebuilt rarely.  .github/workflows/toolchain.yml builds it and pushes it to the GitHub Container Registry.
#
#   docker build -f docker/toolchain.Dockerfile --target toolchain -t quickproof-toolchain:8.20.1 docker
#   docker build -f docker/toolchain.Dockerfile --target ci -t quickproof-toolchain:8.20.1-ci docker
#
# Stages:
#   opam-build   ocaml/opam (multi-arch) + the toolchain built from opam; usable as a "dev" image (has opam)
#   toolchain    ubuntu:24.04 + the opam switch copied at the same path (no opam, no OCaml sources)
#   ci           toolchain + clang with libFuzzer, for the checks of tests/qp.sh that need clang

ARG OPAM_BASE=ocaml/opam:debian-12-ocaml-4.14
# The runtime is Ubuntu 24.04, not Debian 12: the ASan of Debian 12's GCC 12 crashes at start-up in about one run
# in four on kernels with high mmap randomisation (vm.mmap_rnd_bits = 32, as on recent Ubuntu kernels), and a
# container cannot turn ASLR off; the GCC 13 and clang 18 of Ubuntu 24.04 do not.  The switch, built on Debian 12
# (glibc 2.36), runs unchanged on Ubuntu 24.04 (glibc 2.39).
ARG RUNTIME_BASE=ubuntu:24.04

############################################################################################################
FROM ${OPAM_BASE} AS opam-build
ARG JOBS=4
ENV OPAMYES=1 OPAMCONFIRMLEVEL=unsafe-yes OPAMJOBS=${JOBS} OPAMDEPEXTYES=1
# rocq-released has coq-compcert and coq-vst; the default repository has Coq itself and coq-lsp.
RUN opam repo add --all-switches --set-default rocq-released https://rocq-prover.org/opam/released \
 && opam update -y \
 && opam pin add -n -y coq 8.20.1
# Coq together with coq-lsp: coq-lsp needs memprof-limits, an optional dependency of coq-core, and installing it
# later recompiles coq-core and with it CompCert and VST (about 26 more minutes).  menhir 20250912 too, the
# newest that coq-compcert 3.15 accepts: installed later, the downgrade would recompile coq-lsp.
RUN nice -n 15 opam install -y -j ${JOBS} coq.8.20.1 coq-lsp.0.2.5+8.20 menhir.20250912 && opam clean -a -c -s --logs
RUN nice -n 15 opam install -y -j ${JOBS} coq-compcert.3.15 && opam clean -a -c -s --logs
RUN nice -n 15 opam install -y -j ${JOBS} coq-vst.2.15 && opam clean -a -c -s --logs
# CoqHammer's reconstruction tactics (sauto, hauto), which proofs may use; no external ATPs needed.
RUN nice -n 15 opam install -y -j ${JOBS} coq-hammer-tactics.1.3.2+8.20 && opam clean -a -c -s --logs
RUN opam list --installed --columns=name,version > /home/opam/opam-packages.txt
# The runtime copy of the switch, without what only building OCaml code or documentation needs (typed trees,
# bytecode libraries and executables, static archives, coqdoc globs, sources): 2.26 GB -> 1.38 GB.  The OCaml
# standard library (lib/ocaml) stays whole: without its threads.cma findlib reports no package threads.posix and
# coq-lsp/pet stop working, while coqc does not notice.
RUN cp -a /home/opam/.opam/4.14 /home/opam/runtime-switch \
 && cd /home/opam/runtime-switch \
 && find . -path ./lib/ocaml -prune -o \( -name '*.cmt' -o -name '*.cmti' -o -name '*.cma' -o -name '*.glob' \
         -o -name '*.ml' -o -name '*.mli' \) -type f -print0 | xargs -0 rm -f \
 && find lib -path lib/ocaml -prune -o -name '*.a' -type f -print0 | xargs -0 rm -f \
 && find bin -name '*.byte' -type f -delete \
 && rm -rf doc man .opam-switch/sources .opam-switch/backup
# The licenses of the toolchain, shipped with it.  CompCert: INRIA Non-Commercial License (educational, research and
# evaluation use; parts dual-licensed LGPL 2.1); VST: BSD-2-Clause; Coq: LGPL 2.1.
RUN mkdir -p /home/opam/licenses && cd /tmp \
 && opam source coq-compcert.3.15 --dir=cc >/dev/null && cp cc/LICENSE /home/opam/licenses/CompCert-3.15-LICENSE \
 && opam source coq-vst.2.15 --dir=vst >/dev/null && cp vst/LICENSE /home/opam/licenses/VST-2.15-LICENSE \
 && opam source coq-core.8.20.1 --dir=coq >/dev/null && cp coq/LICENSE /home/opam/licenses/Coq-8.20.1-LICENSE \
 && rm -rf cc vst coq

############################################################################################################
FROM ${RUNTIME_BASE} AS toolchain
# gcc (with libasan/libubsan) for qp's native runs; python3, git and patch for qp; libgmp for Coq.  uid 1000 is
# for opam.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      gcc libc6-dev make python3 git patch ca-certificates libgmp10 time less procps \
 && rm -rf /var/lib/apt/lists/* \
 && if id -u ubuntu > /dev/null 2>&1; then userdel -r ubuntu; fi \
 && useradd -m -u 1000 -s /bin/bash opam
# The switch keeps its build-time path, so the absolute paths baked into Coq and findlib stay valid.
COPY --from=opam-build --chown=opam:opam /home/opam/runtime-switch /home/opam/.opam/4.14
COPY --from=opam-build --chown=opam:opam /home/opam/opam-packages.txt /home/opam/opam-packages.txt
COPY --from=opam-build /home/opam/licenses /usr/share/doc/quickproof-toolchain
ENV PATH=/home/opam/.opam/4.14/bin:$PATH \
    OPAM_SWITCH_PREFIX=/home/opam/.opam/4.14 \
    CAML_LD_LIBRARY_PATH=/home/opam/.opam/4.14/lib/stublibs:/home/opam/.opam/4.14/lib/ocaml/stublibs:/home/opam/.opam/4.14/lib/ocaml \
    OCAMLTOP_INCLUDE_PATH=/home/opam/.opam/4.14/lib/toplevel
USER opam
WORKDIR /home/opam
RUN coqc --version && ccomp -version && clightgen -version 2>&1 | head -1 \
 && echo 'Require Import VST.floyd.proofauto. Goal True. exact I. Qed.' > /tmp/t.v && coqc /tmp/t.v && rm /tmp/t.*

############################################################################################################
FROM toolchain AS ci
# clang reads harnesses for qp import-cbmc; its libFuzzer (libclang-rt) is for qp fuzz --libfuzzer and qp fidelity,
# and llvm-symbolizer (llvm) for the crash locations they report.
# The image ends as root: the container jobs of GitHub Actions write to a workspace that belongs to the runner.
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends clang libclang-rt-dev llvm \
 && rm -rf /var/lib/apt/lists/* \
 && printf '#include <stddef.h>\n#include <stdint.h>\nint LLVMFuzzerTestOneInput(const uint8_t *d, size_t n) { return 0; }\n' > /tmp/lf.c \
 && clang -fsanitize=fuzzer,address,undefined /tmp/lf.c -o /tmp/lf && rm /tmp/lf /tmp/lf.c
