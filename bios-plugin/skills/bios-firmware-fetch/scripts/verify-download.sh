#!/usr/bin/env bash
# Verify a downloaded file against a vendor manifest that lists sha256 and size,
# such as Huawei's dbankcdn filelist.xml. The manifest is fetched fresh from the
# vendor host, independently of whatever pointed at the download.
#
# Usage: verify-download.sh <manifest-url-or-path> <file> [entry-name]
#   entry-name   the <spath> of the entry to check (default: the file's basename)
#
# Output: KEY=VALUE lines between === VERIFY === / === END VERIFY ===, then STATUS=.
# Exit 0 only when both sha256 and size match.
set -euo pipefail

manifest=${1:?usage: verify-download.sh <manifest-url-or-path> <file> [entry-name]}
file=${2:?usage: verify-download.sh <manifest-url-or-path> <file> [entry-name]}
entry=${3:-$(basename "$file")}

if [ -f "$manifest" ]; then
  xml=$(cat "$manifest")
else
  xml=$(curl -fsSL -m 30 "$manifest")
fi

# Pull the <file> or <remotefile> block whose <spath> is the entry, then its
# sha256 and size. Huawei lists the package itself under <remotefiles>, and
# small companions such as changelog.xml under <files>.
block=$(awk -v e="$entry" '
  /<(remote)?file>/ {buf=""; inblk=1}
  inblk {buf = buf $0 "\n"}
  /<\/(remote)?file>/ {inblk=0; if (buf ~ "<spath>" e "</spath>") {printf "%s", buf; exit}}' <<<"$xml")

want_sha=$(sed -n 's:.*<sha256>\([0-9A-Fa-f]*\)</sha256>.*:\1:p' <<<"$block" | head -1 | tr 'A-F' 'a-f')
want_size=$(sed -n 's:.*<size>\([0-9]*\)</size>.*:\1:p' <<<"$block" | head -1)

if command -v sha256sum >/dev/null; then
  have_sha=$(sha256sum "$file" | cut -d' ' -f1)
else
  have_sha=$(shasum -a 256 "$file" | cut -d' ' -f1)
fi
have_size=$(wc -c <"$file" | tr -d ' ')

echo "=== VERIFY ==="
echo "ENTRY=$entry"
echo "MANIFEST_SHA256=${want_sha:-missing}"
echo "FILE_SHA256=$have_sha"
echo "MANIFEST_SIZE=${want_size:-missing}"
echo "FILE_SIZE=$have_size"

fail() {
  echo "STATUS=ERROR"
  echo "REASON=$1: $2"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=$1 MSG=$2"
  echo "=== END VERIFY ==="
  exit 1
}
[ -n "$want_sha" ] || fail no_entry "no sha256 for entry '$entry' in the manifest"
[ "$want_sha" = "$have_sha" ] || fail sha256_mismatch "file sha256 differs from the manifest"
[ "$want_size" = "$have_size" ] || fail size_mismatch "file size differs from the manifest"
echo "STATUS=OK"
echo "ISSUE_COUNT=0"
echo "=== END VERIFY ==="
