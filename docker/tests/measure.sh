#!/usr/bin/env bash
# measure.sh IMAGE LOGDIR: the timings of docs/DOCKER.md.  Each step in a fresh container (cold: nothing cached in
# the container), timed; output in LOGDIR/<step>.log.  Scene (b) uses a host directory mounted on /work.
set -uo pipefail
IMG=${1:-quickproof:latest}
L=${2:?usage: measure.sh IMAGE LOGDIR}
mkdir -p "$L"
SOL=$(cd "$(dirname "$0")" && pwd)/count_byte_ok
W=$(mktemp -d "${TMPDIR:-/tmp}/qp-work.XXXX")
chmod 777 "$W"
step() {   # step NAME CMD...: run, time, log
  local name=$1; shift
  local t0 t1 rc
  t0=$(date +%s.%N)
  "$@" > "$L/$name.log" 2>&1; rc=$?
  t1=$(date +%s.%N)
  printf '%-22s rc=%-3s %6.1f s\n' "$name" "$rc" "$(echo "$t1 - $t0" | bc)" | tee -a "$L/summary.txt"
}
run() { docker run --rm --name "quickproof-measure-$$" "$@"; }
echo "# $(date -u +%FT%TZ) image $IMG, host $(nproc) CPUs, load $(cut -d' ' -f1-3 /proc/loadavg)" | tee -a "$L/summary.txt"
step help          run "$IMG"
step list          run "$IMG" list
step show-rle      run "$IMG" show rle
step verify-rle    run "$IMG" verify rle
step verify-adler  run "$IMG" verify adler32
step verify-find   run "$IMG" verify find_byte
step bug           run "$IMG" bug
step check-rle     run "$IMG" check rle
# scene (b): your own project in /work
step b-new         run -v "$W:/work" "$IMG" new demo
step b-check       run -v "$W:/work" "$IMG" check demo
step b-contract    run -v "$W:/work" "$IMG" contract demo
step b-build-adm   run -v "$W:/work" "$IMG" build demo
cp -r "$SOL/src/." "$W/demo-proof/src/" && chmod -R a+rwX "$W"
step b-build       run -v "$W:/work" "$IMG" build demo
step b-verify      run -v "$W:/work" "$IMG" verify demo
echo "work dir: $W" | tee -a "$L/summary.txt"
