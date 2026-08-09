#!/bin/bash

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_tmp=$(mktemp -d)
trap 'rm -rf -- "$test_tmp"' EXIT

mkdir -p "$test_tmp/plugin/scripts" "$test_tmp/bin"
cp "$root/scripts/set-default" "$test_tmp/plugin/scripts/set-default"

cat >"$test_tmp/plugin/scripts/audio-route" <<'STUB'
#!/bin/bash
printf 'route %s\n' "$*" >>"$TEST_LOG"
STUB

cat >"$test_tmp/bin/omarchy-audio-output-set-default" <<'STUB'
#!/bin/bash
printf 'default %s\n' "$*" >>"$TEST_LOG"
STUB

chmod +x "$test_tmp/plugin/scripts/"* "$test_tmp/bin/"*
TEST_LOG="$test_tmp/calls" PATH="$test_tmp/bin:$PATH" \
  "$test_tmp/plugin/scripts/set-default" 42 alsa_output.speaker

diff -u - "$test_tmp/calls" <<'EXPECTED'
route disconnect alsa_output.speaker
default 42 alsa_output.speaker
EXPECTED

printf 'ok - local output selection tears down the network route first\n'
