#!/usr/bin/env bash
# Read or change one field of a UEFI setup variable through efivarfs, the way a
# hidden BIOS setup option is stored. Run as a user with sudo on the target.
#
#   setup-var.sh --var NAME-GUID --offset N [--size 1|2|4] [guards] show
#   setup-var.sh --var NAME-GUID backup [--out FILE]
#   setup-var.sh --var NAME-GUID noop
#   setup-var.sh --var NAME-GUID --offset N [--size 1|2|4] [guards] set VALUE
#   setup-var.sh --var NAME-GUID [guards] restore FILE
#
# Guards (each optional, recommended for `set` and `restore`):
#   --product NAME     /sys/class/dmi/id/product_name must equal NAME
#   --bios VERSION     /sys/class/dmi/id/bios_version must equal VERSION
#   --data-size BYTES  the variable's data size (file size minus the 4-byte
#                      attribute header) must equal BYTES; take it from the
#                      setup form's varstore Size so a layout change is caught
#   --allowed LIST     comma-separated values `set` accepts (from the form's options)
#
# Offsets are VarOffset values from the setup form (IFR), i.e. relative to the
# start of the variable's data, not to the efivarfs file.
#
# Environment: EFIVARS overrides /sys/firmware/efi/efivars, SUDO overrides
# "sudo" (set SUDO= to run without it), DMI overrides /sys/class/dmi/id. These
# exist so the script can be tested against a fake tree.
#
# A wrong write to a setup variable can stop the machine from booting until its
# settings are reset. Run `backup` first, then `noop` to see whether the
# firmware accepts writes, and only then `set`.
set -euo pipefail

EFIVARS=${EFIVARS:-/sys/firmware/efi/efivars}
DMI=${DMI:-/sys/class/dmi/id}
SUDO=${SUDO-sudo}
HDR=4

var="" offset="" size=1 product="" bios="" data_size="" allowed="" out=""
die() { echo "setup-var: $*" >&2; exit 1; }

pos=()
while [ $# -gt 0 ]; do
  case "$1" in
    --var) var=$2; shift 2 ;;
    --offset) offset=$(( $2 )); shift 2 ;;
    --size) size=$2; shift 2 ;;
    --product) product=$2; shift 2 ;;
    --bios) bios=$2; shift 2 ;;
    --data-size) data_size=$(( $2 )); shift 2 ;;
    --allowed) allowed=$2; shift 2 ;;
    --out) out=$2; shift 2 ;;
    -*) die "unknown option $1" ;;
    *) pos+=("$1"); shift ;;
  esac
done
set -- "${pos[@]+"${pos[@]}"}"
cmd=${1:-show}; shift || true
[ -n "$var" ] || die "--var NAME-GUID is required"
case "$size" in 1|2|4) ;; *) die "--size must be 1, 2 or 4" ;; esac

file="$EFIVARS/$var"
$SUDO test -e "$file" || die "no such variable: $file"
[ -z "$product" ] || [ "$(cat "$DMI/product_name")" = "$product" ] || die "product is not $product"
[ -z "$bios" ] || [ "$(cat "$DMI/bios_version")" = "$bios" ] || die "BIOS is not $bios; offsets unverified"
fsize=$($SUDO wc -c < "$file" | tr -d ' ')
[ -z "$data_size" ] || [ "$fsize" -eq $(( HDR + data_size )) ] || die "variable is $((fsize - HDR)) data bytes, expected $data_size"

need_offset() {
  [ -n "$offset" ] || die "--offset is required for $cmd"
  [ $(( HDR + offset + size )) -le "$fsize" ] || die "offset $offset + $size is past the end of the variable"
}

read_value() {  # little-endian unsigned value at the offset
  $SUDO od -An -tu"$size" -j $(( HDR + offset )) -N "$size" "$file" | tr -d ' '
}

write_image() {  # $1 = complete efivarfs image: 4 attribute bytes + data
  # efivarfs files are immutable by default; the write must be a single
  # write() carrying attributes and data together, hence dd with a large bs.
  $SUDO chattr -i "$file"
  $SUDO dd if="$1" of="$file" bs=65536 status=none
}

snapshot() { local t; t=$(mktemp); $SUDO cat "$file" > "$t"; echo "$t"; }

case "$cmd" in
  show)
    need_offset
    echo "value=$(read_value) offset=$offset size=$size var=$var" ;;
  backup)
    out=${out:-$(basename "$var").$(date +%s).bin}
    $SUDO cat "$file" > "$out"
    sha256sum "$out" ;;
  noop)
    t=$(snapshot)
    before=$(sha256sum < "$t")
    write_image "$t"
    after=$($SUDO cat "$file" | sha256sum)
    rm -f "$t"
    if [ "$before" = "$after" ]; then echo "noop write accepted, content unchanged"
    else die "content changed after a no-op write"; fi ;;
  set)
    need_offset
    new=$(( ${1:?usage: set VALUE} ))
    if [ "$new" -lt 0 ] || [ "$new" -ge $(( 1 << (8 * size) )) ]; then
      die "value $new does not fit in $size byte(s)"
    fi
    if [ -n "$allowed" ]; then
      case ",$allowed," in *",$new,"*) ;; *) die "value $new not in allowed list $allowed" ;; esac
    fi
    t=$(snapshot)
    for (( i = 0; i < size; i++ )); do
      printf '%b' "\\$(printf '%03o' $(( (new >> (8 * i)) & 0xff )))" \
        | dd of="$t" bs=1 seek=$(( HDR + offset + i )) conv=notrunc status=none
    done
    # cmp exits 1 when the files differ, which is the expected case here; under
    # pipefail an unguarded cmp would abort the script before the write.
    diffs=$( { cmp -l <($SUDO cat "$file") "$t" || true; } | wc -l)
    [ "$diffs" -le "$size" ] || { rm -f "$t"; die "refusing: $diffs bytes would change"; }
    write_image "$t"; rm -f "$t"
    echo "value=$(read_value) (applies at the next boot)" ;;
  restore)
    f=${1:?usage: restore FILE}
    [ "$(wc -c < "$f" | tr -d ' ')" -eq "$fsize" ] || die "backup size differs from the variable"
    write_image "$f"
    echo "restored $var from $f" ;;
  *) die "unknown command $cmd" ;;
esac
