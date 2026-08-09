#!/bin/bash

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

bash -n "$root/scripts/audio-output" "$root/scripts/audio-route" \
  "$root/scripts/set-default" "$root/setup.sh"
python3 -m py_compile \
  "$root/scripts/cast-stream" \
  "$root/scripts/cast-volume" \
  "$root/scripts/speaker-discovery"
PYTHONPATH="$root" python3 -m unittest discover -s "$root/test" -p 'test_*.py' -v
node "$root/test/model-test.js"
"$root/test/route-test.sh"
"$root/test/set-default-test.sh"
omarchy plugin validate "$root"

grep -Fq 'Qt.resolvedUrl("scripts/audio-output")' "$root/Panel.qml"
grep -Fq 'Model.filterWifiSpeakers(discoveredWifiSpeakers, rawAudioSinks)' "$root/Panel.qml"
jq -e '
  .id == "stappmus.audio"
  and .kinds == ["bar-widget"]
  and .entryPoints.barWidget == "Panel.qml"
  and .omarchy.clonedFrom == "omarchy.audio"
' "$root/manifest.json" >/dev/null
[[ ! -e $root/WifiSpeakers.qml && ! -e $root/scripts/open-overlay ]]
if grep -Fq 'easyeffects_sink' "$root/scripts/audio-output" "$root/scripts/audio-route"; then
  echo 'not ok - routing must not depend on the legacy EasyEffects sink' >&2
  exit 1
fi
