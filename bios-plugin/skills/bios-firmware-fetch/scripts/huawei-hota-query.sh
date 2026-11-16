#!/usr/bin/env bash
# Ask Huawei's PC Manager / DriverTools update service (HOTA) for the newest
# package of one component for one device, and print where its manifest lives.
#
# Usage: huawei-hota-query.sh <DeviceName> [componentID] [packageName] [region]
#   DeviceName   Huawei's internal model code, e.g. MachC (see references/huawei-hota.md)
#   componentID  23 = BIOS on the models checked so far (default 23)
#   packageName  BIOS (default)
#   region       eu (default) or cn
#
# The request carries a random 16-hex deviceId, never anything from this machine.
# Output: KEY=VALUE lines between === HOTA === / === END HOTA ===, then STATUS=.
set -euo pipefail

device=${1:?usage: huawei-hota-query.sh <DeviceName> [componentID] [packageName] [region]}
component=${2:-23}
package=${3:-BIOS}
region=${4:-eu}

case "$region" in
  eu) host=https://update-dre.platform.hicloud.com ;;
  cn) host=https://update-drcn.platform.hicloud.com ;;
  *) echo "STATUS=ERROR"; echo "REASON=region must be eu or cn"; exit 2 ;;
esac
endpoint="$host/hid_and_common/v2/CheckEx.action?latest=true&verType=true&defenceHijack=true"

device_id=$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')
body=$(jq -cn --arg dev "$device" --arg comp "$component" --arg pkg "$package" --arg id "$device_id" \
  '{components:[{PackageVersionCode:"1.0.0.0",componentID:$comp,PackageName:$pkg}],
    rules:{C_version:"C233",Language:"en-US",OS:"Windows",deviceId:$id,DeviceName:$dev}}')

response=$(curl -sS -m 30 -X POST -H 'Content-Type: application/json' -d "$body" "$endpoint")

echo "=== HOTA ==="
echo "DEVICE=$device"
echo "COMPONENT_ID=$component"
echo "ENDPOINT=$host"
service_status=$(jq -r '.status // "missing"' <<<"$response")
echo "SERVICE_STATUS=$service_status"

count=$(jq '[.components[]?] | length' <<<"$response")
echo "COMPONENT_COUNT=$count"
jq -r '.components[]? | "NAME=\(.name)\nVERSION=\(.version)\nCREATED=\(.createTime)\nBASE_URL=\(.url)\nMANIFEST_URL=\(.url)full/filelist.xml\nCHANGELOG_URL=\(.url)full/changelog.xml"' <<<"$response"
if [ "$service_status" = 0 ] && [ "$count" -gt 0 ]; then
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
else
  echo "STATUS=WARN"
  echo "REASON=no_package: no package for DeviceName=$device componentID=$component (service status $service_status)"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=WARN TYPE=no_package MSG=no package for DeviceName=$device componentID=$component (service status $service_status)"
fi
echo "=== END HOTA ==="
