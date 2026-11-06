#!/usr/bin/env bash
# Queue an unsigned tvOS IPA for install through a running atvLoadly instance.
# atvLoadly signs with your burner Apple ID and pushes to the paired Apple TV.
#
# Usage:
#   ./install-sideload-ipa.sh
#   ./install-sideload-ipa.sh path/to/Rivulet-unsigned.ipa
#
# Env overrides (optional):
#   ATVLOADLY_URL=http://127.0.0.1:5533
#   ATVLOADLY_ACCOUNT=courage.samg@gmail.com
#   ATVLOADLY_DEVICE_ID=<id>               # required if more than one device
#   ATVLOADLY_CUSTOM_NAME=Rivulet Sideload # optional home-screen name
#   ATVLOADLY_REMOVE_EXTENSIONS=false      # true drops Top Shelf / asset packs
#   ATVLOADLY_WAIT=1                       # poll until the install queue empties

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

ATVLOADLY_URL="${ATVLOADLY_URL:-http://127.0.0.1:5533}"
ATVLOADLY_URL="${ATVLOADLY_URL%/}"
IPA="${1:-build/sideload/ipa/Rivulet-unsigned.ipa}"
WAIT="${ATVLOADLY_WAIT:-0}"
REMOVE_EXT="${ATVLOADLY_REMOVE_EXTENSIONS:-false}"
ACCOUNT="${ATVLOADLY_ACCOUNT:-courage.samg@gmail.com}"

die() { echo "error: $*" >&2; exit 1; }

command -v curl >/dev/null || die "curl not found"
command -v python3 >/dev/null || die "python3 not found"

[[ -f "$IPA" ]] || die "IPA not found: $IPA
  Build one first: ./build-sideload-ipa.sh"

# Reachability
if ! curl -fsS --max-time 3 "$ATVLOADLY_URL/" >/dev/null; then
  die "atvLoadly is not reachable at $ATVLOADLY_URL
  Open the atvLoadly app (or start its Docker container) and try again."
fi

json_get() {
  # json_get <json> <python-expr-using-data>
  local json="$1"
  local expr="$2"
  ATV_JSON="$json" python3 -c "
import json, os, sys
raw = os.environ['ATV_JSON']
try:
    body = json.loads(raw)
except Exception as e:
    sys.stderr.write(f'bad JSON: {e}\\n')
    sys.exit(2)
if isinstance(body, dict) and body.get('code', 200) not in (200, 0, None):
    msg = body.get('msg') or body.get('message') or raw
    sys.stderr.write(str(msg) + '\\n')
    sys.exit(1)
data = body.get('data', body) if isinstance(body, dict) else body
val = ($expr)
if val is None:
    sys.exit(3)
if isinstance(val, (list, dict)):
    print(json.dumps(val))
else:
    print(val)
"
}

# Device: env, else the only paired device.
DEVICE_ID="${ATVLOADLY_DEVICE_ID:-}"
DEVICES_JSON="$(curl -fsS "$ATVLOADLY_URL/api/devices")"
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(json_get "$DEVICES_JSON" "data[0]['id'] if isinstance(data, list) and len(data)==1 else None" 2>/dev/null || true)"
fi
if [[ -z "$DEVICE_ID" ]]; then
  echo "Paired devices:" >&2
  json_get "$DEVICES_JSON" "[{'id':d.get('id'),'name':d.get('name'),'status':d.get('status')} for d in data] if isinstance(data, list) else data" >&2 || true
  die "set ATVLOADLY_DEVICE_ID to one of the ids above (or pair exactly one Apple TV)"
fi

FORM=(
  -F "account=$ACCOUNT"
  -F "file=@${IPA};type=application/octet-stream"
  -F "device_id=$DEVICE_ID"
  -F "remove_extensions=$REMOVE_EXT"
  -F "signing_mode=apple_id"
)
if [[ -n "${ATVLOADLY_CUSTOM_NAME:-}" ]]; then
  FORM+=(-F "custom_name=$ATVLOADLY_CUSTOM_NAME")
fi

echo "==> Installing via atvLoadly at $ATVLOADLY_URL"
echo "    IPA:     $IPA ($(du -h "$IPA" | awk '{print $1}'))"
echo "    Account: $ACCOUNT"
[[ -n "$DEVICE_ID" ]] && echo "    Device:  $DEVICE_ID"
[[ -n "${ATVLOADLY_CUSTOM_NAME:-}" ]] && echo "    Name:    $ATVLOADLY_CUSTOM_NAME"

RESP="$(curl -fsS -X POST "$ATVLOADLY_URL/api/install" "${FORM[@]}")" \
  || die "POST /api/install failed"

MSG="$(json_get "$RESP" "data.get('message') if isinstance(data, dict) else None" 2>/dev/null || true)"
DEVICE_NAME="$(json_get "$RESP" "data.get('device') if isinstance(data, dict) else None" 2>/dev/null || true)"
STATUS="$(json_get "$RESP" "data.get('status') if isinstance(data, dict) else None" 2>/dev/null || true)"

echo "    Queued:  ${STATUS:-ok}${MSG:+ — $MSG}${DEVICE_NAME:+ → $DEVICE_NAME}"
echo "    Watch progress in atvLoadly, or: curl -s $ATVLOADLY_URL/api/apps/installing"

if [[ "$WAIT" == "1" || "$WAIT" == "true" ]]; then
  echo "==> Waiting for install queue to drain…"
  while true; do
    Q="$(curl -fsS "$ATVLOADLY_URL/api/apps/installing")"
    N="$(json_get "$Q" "len(data) if isinstance(data, list) else (0 if data in (None, []) else 1)" 2>/dev/null || echo 0)"
    if [[ "$N" == "0" ]]; then
      echo "    Install queue empty."
      break
    fi
    echo "    still installing ($N)…"
    sleep 5
  done
  echo "Done. Check the Apple TV home screen (and atvLoadly → Apps) for the result."
fi
