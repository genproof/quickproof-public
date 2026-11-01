#!/usr/bin/env bash
# docker/build.sh [toolchain]: builds the QuickProof image (docker/quickstart.Dockerfile) from this checkout.
# It never pushes anything.
#
#   docker/build.sh              the image quickproof:latest, from the commit checked out (HEAD), on the
#                                toolchain image quickproof-toolchain:8.20.1
#   docker/build.sh toolchain    the toolchain image first, from docker/toolchain.Dockerfile (40 to 60 minutes
#                                at 4 jobs), then the image
#
# The image gets the commit HEAD, not the working tree: commit what you want in it.  It gets that commit with
# its hash but without the history before it (a shallow clone), in /opt/quickproof.  The projects made in the
# image pin that commit, and qp outside the image fetches a pinned commit from the public repository, so build
# an image for other people from a commit that the public repository has.
#
# Environment:
#   QP_IMAGE            the tag of the image (default quickproof:latest)
#   QP_TOOLCHAIN_IMAGE  the toolchain image to build on (default quickproof-toolchain:8.20.1, the tag that
#                       `docker/build.sh toolchain` builds; the published one is
#                       ghcr.io/genproof/quickproof-toolchain:8.20.1)
#   QP_JOBS             parallel jobs of the builds in the image (default 4)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=${QP_IMAGE:-quickproof:latest}
TOOLCHAIN=${QP_TOOLCHAIN_IMAGE:-quickproof-toolchain:8.20.1}
JOBS=${QP_JOBS:-4}

case ${1:-} in
  '') ;;
  toolchain)
    docker build -f "$ROOT/docker/toolchain.Dockerfile" --target toolchain --build-arg JOBS="$JOBS" \
      -t "$TOOLCHAIN" "$ROOT/docker" ;;
  *) echo "usage: docker/build.sh [toolchain]" >&2; exit 2 ;;
esac
if ! docker image inspect "$TOOLCHAIN" > /dev/null 2>&1 && [[ $TOOLCHAIN != */* ]]; then
  echo "docker/build.sh: there is no image $TOOLCHAIN.  Build it with \`docker/build.sh toolchain\`, or build on" >&2
  echo "the published one: QP_TOOLCHAIN_IMAGE=ghcr.io/genproof/quickproof-toolchain:8.20.1 docker/build.sh" >&2
  exit 1
fi

head=$(git -C "$ROOT" rev-parse HEAD)
branch=$(git -C "$ROOT" symbolic-ref -q --short HEAD || echo main)
if [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]; then
  echo "docker/build.sh: note: the checkout has uncommitted changes, which are not in the image" >&2
fi
ctx=$(mktemp -d "${TMPDIR:-/tmp}/quickproof-image.XXXXXX")
trap 'rm -rf "$ctx"' EXIT
git init -q "$ctx/quickproof"
git -C "$ctx/quickproof" fetch -q --depth 1 "file://$ROOT" "$head"
git -C "$ctx/quickproof" checkout -q -b "$branch" "$head"
git -C "$ctx/quickproof" remote add origin https://github.com/genproof/quickproof-public.git
echo "docker/build.sh: $IMAGE from $branch at ${head:0:12}, on $TOOLCHAIN"
docker build -f "$ROOT/docker/quickstart.Dockerfile" --build-arg TOOLCHAIN="$TOOLCHAIN" \
  --build-arg JOBS="$JOBS" --build-arg REVISION="$head" -t "$IMAGE" "$ctx"
echo "built $IMAGE"
