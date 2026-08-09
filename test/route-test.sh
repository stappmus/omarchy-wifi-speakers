#!/bin/bash

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
route="$root/scripts/audio-route"
test_tmp=$(mktemp -d)
trap 'rm -rf -- "$test_tmp"' EXIT

stub_dir="$test_tmp/bin"
runtime_dir="$test_tmp/runtime"
route_log="$test_tmp/route.log"
default_sink_file="$test_tmp/default-sink"
pw_dump_count_file="$test_tmp/pw-dump-count"
mkdir -p "$stub_dir" "$runtime_dir"
printf 'omarchy_speaker_tuning\n' >"$default_sink_file"
printf '0\n' >"$pw_dump_count_file"
: >"$route_log"

cat >"$stub_dir/pactl" <<'STUB'
#!/bin/bash
printf 'pactl %s\n' "$*" >>"$TEST_ROUTE_LOG"
case "${1:-} ${2:-} ${3:-}" in
  "load-module module-null-sink "*) printf '42\n' ;;
  "list short sinks")
    printf '1\tomarchy_speaker_tuning\tmodule\tRUNNING\n'
    printf '2\tomarchy_wifi_cast_12345678123412341234123456789abc\tmodule\tRUNNING\n'
    printf '3\traop_sink.stappmus_wifi_aabbcc\tmodule\tRUNNING\n'
    ;;
  "get-default-sink  ") cat "$TEST_DEFAULT_SINK_FILE" ;;
esac
STUB

cat >"$stub_dir/pw-dump" <<'STUB'
#!/bin/bash
count=0
[[ -r $TEST_PW_DUMP_COUNT ]] && read -r count <"$TEST_PW_DUMP_COUNT"
count=$((count + 1))
printf '%s\n' "$count" >"$TEST_PW_DUMP_COUNT"
if ((count <= ${TEST_PW_DUMP_FAILS:-0})); then
  printf '[]\n'
  exit 0
fi
cat <<'JSON'
[
  {"id":1,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omarchy_speaker_tuning"}}},
  {"id":2,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omarchy_wifi_cast_12345678123412341234123456789abc"}}},
  {"id":3,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"raop_sink.stappmus_wifi_aabbcc"}}}
]
JSON
STUB

cat >"$stub_dir/systemd-run" <<'STUB'
#!/bin/bash
printf 'systemd-run %s\n' "$*" >>"$TEST_ROUTE_LOG"
arguments=("$@")
for ((index = 0; index < ${#arguments[@]}; index++)); do
  if [[ ${arguments[$index]} == --ready-file ]]; then
    printf 'http://192.168.1.20:49785/stream.wav\n' >"${arguments[$((index + 1))]}"
  fi
done
STUB

cat >"$stub_dir/systemctl" <<'STUB'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$TEST_ROUTE_LOG"
exit 0
STUB

cat >"$stub_dir/omarchy-audio-output-set-default" <<'STUB'
#!/bin/bash
printf 'output-default %s\n' "$*" >>"$TEST_ROUTE_LOG"
printf '%s\n' "$2" >"$TEST_DEFAULT_SINK_FILE"
STUB

chmod +x "$stub_dir"/*

route_env=(
  XDG_RUNTIME_DIR="$runtime_dir"
  TEST_ROUTE_LOG="$route_log"
  TEST_DEFAULT_SINK_FILE="$default_sink_file"
  TEST_PW_DUMP_COUNT="$pw_dump_count_file"
  TEST_PW_DUMP_FAILS=2
  PATH="$stub_dir:$PATH"
)

speaker_id=12345678-1234-1234-1234-123456789abc
cast_sink=omarchy_wifi_cast_12345678123412341234123456789abc
env "${route_env[@]}" "$route" connect cast \
  "$speaker_id" "Living Room" 192.168.1.20 8009 "Nest Audio"
grep -Fxq "$cast_sink" "$default_sink_file"
(( $(<"$pw_dump_count_file") >= 3 ))
grep -Fq $'cast\tomarchy-audio-cast-12345678123412341234123456789abc.service' \
  "$runtime_dir/omarchy-audio-wifi.state"
status=$(env "${route_env[@]}" "$route" status)
[[ $(jq -r .status <<<"$status") == connected ]]
[[ $(jq -r .kind <<<"$status") == cast ]]

env "${route_env[@]}" "$route" disconnect
[[ ! -e $runtime_dir/omarchy-audio-wifi.state ]]
grep -Fxq 'omarchy_speaker_tuning' "$default_sink_file"
grep -Fq 'pactl unload-module 42' "$route_log"

: >"$route_log"
env "${route_env[@]}" "$route" connect raop \
  AABBCC Kitchen AABBCC@Kitchen kitchen.local 192.168.1.21 7000 udp RSA:PCM AudioAccessory
grep -Fxq 'raop_sink.stappmus_wifi_aabbcc' "$default_sink_file"
grep -Fq $'raop\tomarchy-audio-raop-aabbcc.service' \
  "$runtime_dir/omarchy-audio-wifi.state"
grep -Fq 'libpipewire-module-raop-sink' "$route_log"
status=$(env "${route_env[@]}" "$route" status)
[[ $(jq -r .status <<<"$status") == connected ]]
[[ $(jq -r .kind <<<"$status") == raop ]]

env "${route_env[@]}" "$route" disconnect
grep -Fxq 'omarchy_speaker_tuning' "$default_sink_file"

printf 'ok - Cast and AirPlay routes preserve and restore the Quattro default sink\n'
