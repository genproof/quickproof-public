#!/usr/bin/env bash
# make-examples.sh: run once when the image is built (docker/quickstart.Dockerfile).  It makes the proof
# repositories of the framework's examples the way any proof is made with QuickProof, and the bug scene of
# `qpdemo bug`.  The framework is /opt/quickproof; everything is written under /opt/qp-examples:
#
#   upstream/NAME       the code of examples/NAME, committed to a git repository that stands in for an upstream
#   ws/projects/NAME    the project of examples/NAME, pinned to that commit and to the framework of the image
#   repos/NAME          `qp assemble` (the contract, tag `contract`), then the files of examples/NAME/proof
#                       committed on top: what `qpdemo verify NAME` checks with qp verify
#   history/rle         the bug scene: rle 1.0 (examples/rle) and rle 2.0, which is rle 1.0 with
#                       docker/quickstart/rle-2.0.patch applied, as tags v1.0 and v2.0
#   ws/projects/rle2    the law of rle 1.0 (examples/rle/harness), pinned to rle 2.0, where it is false
#
# Every commit made here has a fixed date and author, so the same framework gives the same commits.
set -euo pipefail
X=/opt/qp-examples
FW=/opt/quickproof
G=(git -c user.name=quickproof -c user.email=quickproof@localhost -c init.defaultBranch=main -c commit.gpgsign=false)
export GIT_AUTHOR_DATE=2026-01-01T00:00:00+00:00 GIT_COMMITTER_DATE=2026-01-01T00:00:00+00:00
mkdir -p "$X/repos" "$X/upstream" "$X/ws/projects" "$X/history"

code_of() { bash -c '. "$1"; echo $CODE' _ "$1"; }   # CODE of a project.conf

names=()
for ex in "$FW"/examples/*/; do
  name=$(basename "$ex")
  [ -f "$ex/project.conf" ] || continue
  up=$X/upstream/$name pd=$X/ws/projects/$name
  rm -rf "$up" "$pd"; mkdir -p "$up" "$pd"
  for c in $(code_of "$ex/project.conf"); do
    mkdir -p "$up/$(dirname "$c")"; cp -r "$ex/$c" "$up/$c"
  done
  (cd "$up" && "${G[@]}" init -q && "${G[@]}" add -A && "${G[@]}" commit -q -m "The code of the example $name")
  commit=$(git -C "$up" rev-parse HEAD)
  for f in quickproof.conf env.c env harness patch notes.md; do
    if [ -e "$ex/$f" ]; then cp -r "$ex/$f" "$pd/"; fi
  done
  sed -e "s|^UPSTREAM=.*|UPSTREAM=$up|" -e "s|^COMMIT=.*|COMMIT=$commit|" "$ex/project.conf" > "$pd/project.conf"
  names+=("$name")
done
[ ${#names[@]} -gt 0 ] || { echo "make-examples.sh: no examples in $FW/examples" >&2; exit 1; }

for name in "${names[@]}"; do
  repo=$X/repos/$name
  rm -rf "$repo"
  qp --workspace "$X/ws" assemble "$name" "$repo"
  cp -r "$FW/examples/$name/proof/src/." "$repo/src/"
  (cd "$repo" && "${G[@]}" add -A && "${G[@]}" commit -q -m "Proof of the laws of $name")
  echo "example $name: $(git -C "$repo" log --oneline | wc -l) commits, contract $(git -C "$repo" rev-parse --short contract)"
done

# The bug scene: rle 2.0 breaks the law that rle 1.0 obeys.
h=$X/history/rle
rm -rf "$h"; mkdir -p "$h"
cp "$FW/examples/rle/rle.c" "$FW/examples/rle/rle.h" "$h/"
(cd "$h" && "${G[@]}" init -q && "${G[@]}" add -A && "${G[@]}" commit -q -m "rle 1.0" && "${G[@]}" tag v1.0 \
   && "${G[@]}" apply "$FW/docker/quickstart/rle-2.0.patch" \
   && "${G[@]}" commit -q -a -m "rle 2.0: simpler loop" && "${G[@]}" tag v2.0)
pd=$X/ws/projects/rle2
rm -rf "$pd"; mkdir -p "$pd"
cp -r "$FW/examples/rle/quickproof.conf" "$FW/examples/rle/harness" "$pd/"
cat > "$pd/project.conf" <<EOF
# The project rle2 (docs/QP.md): the law of examples/rle, on rle 2.0, where it is false (qpdemo bug).
UPSTREAM=$h
COMMIT=$(git -C "$h" rev-parse v2.0)   # v2.0
FRAMEWORK=
LOGICAL=Rle2
CODE="rle.c rle.h"
PATCH=""
EOF
echo "bug scene: rle 1.0 $(git -C "$h" rev-parse --short v1.0), rle 2.0 $(git -C "$h" rev-parse --short v2.0)"
