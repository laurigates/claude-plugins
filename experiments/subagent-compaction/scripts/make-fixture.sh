#!/usr/bin/env bash
# Generate the filler corpus a probe subagent reads.
#
# Each file is ~<kb> KiB of pseudo-random words (small enough for one Read call)
# ending in a `SENTINEL <file> <hex>` line. The sentinel list is the ground truth
# the analyzer scores the subagent's final report against: a sentinel the agent
# never saw in its *current* context cannot be recalled after compaction, so a
# correct-looking one it did not read is a fabrication.
#
# Usage: make-fixture.sh <dir> [count=20] [kb=60]
set -euo pipefail

dir="${1:?usage: make-fixture.sh <dir> [count] [kb]}"
count="${2:-20}"
kb="${3:-60}"

mkdir -p "$dir/files"
: > "$dir/sentinels.txt"

for i in $(seq 1 "$count"); do
  name="$(printf 'f%02d.txt' "$i")"
  f="$dir/files/$name"
  awk -v seed="$i" -v bytes="$((kb * 1024))" 'BEGIN {
    n = split("alpha bravo charlie delta echo foxtrot golf hotel india juliett kilo lima mike november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee zulu", w, " ")
    srand(seed); line = 0; total = 0
    while (total < bytes) {
      s = sprintf("L%05d", ++line)
      for (k = 0; k < 10; k++) s = s " " w[int(rand() * n) + 1]
      print s; total += length(s) + 1
    }
  }' > "$f"
  hex="$(printf 'ctx-probe-%s-%s-%s' "$i" "$kb" "$count" | sha256sum | cut -c1-12)"
  printf 'SENTINEL %s %s\n' "$name" "$hex" | tee -a "$dir/sentinels.txt" >> "$f"
done

echo "FIXTURE_DIR=$dir"
echo "FIXTURE_FILES=$count"
echo "FIXTURE_KB_PER_FILE=$kb"
