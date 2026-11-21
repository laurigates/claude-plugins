#!/usr/bin/env bash
# Offline test for drain-calc.py with rows shaped like real measurements.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tool="$here/../drain-calc.py"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# A clean 79-minute off-state run (0.337 Wh drop) and a suspend run during which
# the gauge raised energy_full and energy_now rose.
cat > "$tmp/log.csv" <<'EOF'
epoch,phase,status,energy_uwh,energy_full_uwh,capacity,voltage_uv,ac_online
1794737484,before,Discharging,42570000,53686000,79,8169000,0
1794742280,after,Discharging,42233000,53686000,78,7717000,0
1794816067,before,Discharging,53120000,53541000,99,8622000,0
1794823288,after,Discharging,54824000,55565000,98,8551000,0
EOF

out=$(python3 -I "$tool" "$tmp/log.csv")
pass=0 fail=0
expect() { if grep -q -- "$2" <<<"$out"; then pass=$((pass+1)); else echo "FAIL: $1"; fail=$((fail+1)); fi; }
expect "two pairs" "PAIRS=2"
expect "clean run drop" "DROP_WH=0.337"
expect "clean run average" "AVG_MW=253"
expect "recalibration flagged" "gauge recalibrated"
expect "energy rise flagged" "energy rose on battery"
expect "soc estimate printed" "SOC_ESTIMATE_MW=149"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
