#!/bin/bash

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

bash -n "$root/scripts/audio-output" "$root/scripts/audio-route" \
  "$root/scripts/open-overlay" "$root/setup.sh"
python3 -m py_compile \
  "$root/scripts/cast-stream" \
  "$root/scripts/cast-volume" \
  "$root/scripts/speaker-discovery"
PYTHONPATH="$root" python3 -m unittest discover -s "$root/test" -p 'test_*.py' -v
"$root/test/route-test.sh"

grep -Fq 'Qt.resolvedUrl("scripts/audio-output")' "$root/WifiSpeakers.qml"
grep -Fq '[backendPath, "connect", row.speakerId, row.protocol]' "$root/WifiSpeakers.qml"
jq -e '.keepLoaded != true' "$root/manifest.json" >/dev/null
if grep -Fq 'easyeffects_sink' "$root/scripts/audio-output" "$root/scripts/audio-route"; then
  echo 'not ok - routing must not depend on the legacy EasyEffects sink' >&2
  exit 1
fi
