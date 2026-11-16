#!/usr/bin/env bash
# Build thisiseth/esp32-serprog for a Seeed XIAO ESP32-S3 from a pinned upstream
# commit plus the XIAO pin patch in this directory.
#
# Usage: build-xiao-serprog.sh [WORK_DIR]
# Env:   IDF_PATH  ESP-IDF >= 6.0 checkout (default: ~/esp/esp-idf)
#
# Outputs under WORK_DIR (default: ./esp32-serprog-build):
#   esp32-serprog/      upstream clone
#   xiao-serprog-out/   binaries + flash_args
set -euo pipefail

readonly UPSTREAM_URL="https://github.com/thisiseth/esp32-serprog.git"
readonly UPSTREAM_SHA="0ca3c7e6d3099ed08b1aaaab80a4f3af64d97275"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="${1:-${PWD}/esp32-serprog-build}"
mkdir -p "${work_dir}"
readonly patch_file="${script_dir}/xiao-esp32s3-pins.patch"
readonly src_dir="${work_dir}/esp32-serprog"
readonly proj_dir="${src_dir}/src/serprog"
readonly out_dir="${work_dir}/xiao-serprog-out"
idf_path="${IDF_PATH:-${HOME}/esp/esp-idf}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ -f "${idf_path}/export.sh" ]] || die "no ESP-IDF at ${idf_path} (set IDF_PATH)"

# 1. Upstream source at the pinned commit, with only the pin patch applied.
if [[ ! -d "${src_dir}/.git" ]]; then
  git clone --quiet "${UPSTREAM_URL}" "${src_dir}"
fi
git -C "${src_dir}" fetch --quiet origin
git -C "${src_dir}" checkout --quiet --force "${UPSTREAM_SHA}"
git -C "${src_dir}" clean --quiet -fdx
git -C "${src_dir}" apply "${patch_file}"

# 2. Build. export.sh is sourced only inside this script's shell.
# shellcheck source=/dev/null
. "${idf_path}/export.sh" >/dev/null
idf_ver="$(idf.py --version)"
case "${idf_ver}" in
  *v[6-9].*) ;;
  *) die "ESP-IDF >= 6.0 required, found: ${idf_ver}" ;;
esac
idf.py -C "${proj_dir}" set-target esp32s3
idf.py -C "${proj_dir}" build

# Transport must be USB Serial/JTAG and Wi-Fi must be off.
cfg="${proj_dir}/sdkconfig"
grep -qx 'CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG=y' "${cfg}" || die "console is not USB Serial/JTAG"
grep -qx 'CONFIG_ESP32_SERPROG_WIFI_DISABLED=y' "${cfg}" || die "Wi-Fi transport is enabled"

# 3. Collect outputs.
build_dir="${proj_dir}/build"
mkdir -p "${out_dir}"
cp "${build_dir}/bootloader/bootloader.bin" \
   "${build_dir}/partition_table/partition-table.bin" \
   "${build_dir}/main.bin" \
   "${build_dir}/flash_args" \
   "${out_dir}/"

printf '\nESP-IDF: %s\nupstream: %s @ %s\noutput: %s\n\n' \
  "${idf_ver}" "${UPSTREAM_URL}" "${UPSTREAM_SHA}" "${out_dir}"
(cd "${out_dir}" && wc -c -- *.bin && shasum -a 256 -- *.bin)
printf '\nflash_args:\n'
cat "${out_dir}/flash_args"
