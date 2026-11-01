#!/usr/bin/env bash
# asan_check.sh [IMAGE] [N]: does AddressSanitizer start reliably in the image on this host?  Debian 12's GCC 12
# ASan crashes at start-up in about one run in four on kernels with vm.mmap_rnd_bits = 32, and a container cannot
# turn ASLR off; the image is on Ubuntu 24.04 (GCC 13) for that reason.
#   1. a trivial program built with -fsanitize=address,undefined, started 200 times: the start-up crashes;
#   2. `qpdemo check` of the template law (`qpdemo new`), N times (default 20), each in a fresh container: every run
#      must have the law pass its 1000 native runs and its mutant baseline, with no sanitizer start-up crash.
# Exit 0 = no crash.  The logs go to LOGDIR (default: a new temporary directory).
set -uo pipefail
IMG=${1:-quickproof:latest}
N=${2:-20}
HERE=$(cd "$(dirname "$0")" && pwd)
L=${LOGDIR:-$(mktemp -d "${TMPDIR:-/tmp}/qp-asan-logs.XXXX")}
mkdir -p "$L"
W=$(mktemp -d "${TMPDIR:-/tmp}/qp-asan.XXXX"); chmod 777 "$W"
echo "# $(date -u +%FT%TZ) $IMG; $(docker run --rm --entrypoint gcc "$IMG" --version | head -1)" | tee "$L/summary.txt"

docker run --rm --entrypoint bash "$IMG" -c '
  cd /tmp && printf "int main(void){return 0;}\n" > a.c && gcc -fsanitize=address,undefined -g a.c -o a
  bad=0; for i in $(seq 200); do ./a 2>/dev/null || bad=$((bad + 1)); done; echo "start-up crashes of an ASan program: $bad/200"' \
  | tee -a "$L/summary.txt"
startup=$(grep -o '[0-9]*/200' "$L/summary.txt" | tail -1 | cut -d/ -f1)

docker run --rm -v "$W:/work" "$IMG" new law > /dev/null 2>&1
crashes=0
for i in $(seq "$N"); do
  t0=$(date +%s)
  docker run --rm -v "$W:/work" "$IMG" check law > "$L/check-$i.log" 2>&1
  native=$(grep -o 'upstream  .*' "$L/check-$i.log" | head -1)
  killed=$(grep -o 'Killed by some harness: \*\*[0-9/]*\*\*' "$L/check-$i.log" | grep -o '[0-9]*/[0-9]*')
  sig=$(grep -c -E 'AddressSanitizer:DEADLYSIGNAL|Shadow memory range|no summary|Not counted|FAILED' "$L/check-$i.log")
  ok=yes; { [ "$native" = "upstream  ok (1000 runs)" ] && [ "$sig" = 0 ] && [ -n "$killed" ]; } || { ok=NO; crashes=$((crashes + 1)); }
  printf 'check %2d: %-28s mutants killed %-5s crash signs %s  %s (%d s)\n' "$i" "$native" "$killed" "$sig" "$ok" \
    $(( $(date +%s) - t0 )) | tee -a "$L/summary.txt"
done
echo "qpdemo check runs with a crash: $crashes/$N; ASan start-up crashes: $startup/200" | tee -a "$L/summary.txt"
exit $(( crashes > 0 || startup > 0 ))
