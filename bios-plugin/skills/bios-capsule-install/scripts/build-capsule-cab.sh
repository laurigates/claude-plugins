#!/usr/bin/env bash
# Wrap a vendor UEFI capsule image into a fwupd cabinet with fwupd's own
# firmware_packager.py. Run on the machine that will install it.
#
# Usage: build-capsule-cab.sh --bin <image> --sha256 <hex> --guid <esrt-fw-class> \
#          --version <esrt-integer> --name <firmware name> --vendor <developer> \
#          --out <file.cab> [--description <text>]
#
# --version is the ESRT integer the firmware will report after the update. It
# must be greater than the current ESRT fw_version, or fwupd treats it as a
# downgrade. --sha256 pins the image so a swapped file fails before packaging.
set -euo pipefail

bin="" sha="" guid="" version="" fw_name="" vendor="" out="" desc=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bin) bin=$2 ;; --sha256) sha=$2 ;; --guid) guid=$2 ;; --version) version=$2 ;;
    --name) fw_name=$2 ;; --vendor) vendor=$2 ;; --out) out=$2 ;; --description) desc=$2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift 2
done
for v in bin sha guid version fw_name vendor out; do
  [ -n "${!v}" ] || { echo "missing --${v/fw_name/name}" >&2; exit 2; }
done

packager=/usr/share/fwupd/firmware_packager.py
[ -f "$packager" ] || { echo "fwupd's $packager not found" >&2; exit 1; }
command -v gcab >/dev/null || { echo "gcab not installed (firmware_packager.py calls it)" >&2; exit 1; }

echo "$sha  $bin" | sha256sum -c -

# --bin must be absolute when no --exe is given: the packager resolves it
# relative to its own temporary directory otherwise.
abs_bin=$(cd "$(dirname "$bin")" && pwd)/$(basename "$bin")

python3 "$packager" \
  --firmware-name "$fw_name" \
  --firmware-summary "$fw_name" \
  --device-guid "$guid" \
  --developer-name "$vendor" \
  --release-version "$version" \
  --version-format number \
  --update-protocol org.uefi.capsule \
  --release-description "${desc:-$fw_name}" \
  --bin "$abs_bin" \
  --out "$out"

sha256sum "$out"
echo "Inspect it against this machine with: sudo fwupdtool get-details $out"
