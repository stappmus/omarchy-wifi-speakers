#!/bin/bash

set -euo pipefail

readonly plugin_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly installed_root="$HOME/.config/omarchy/plugins/stappmus.audio"
readonly source_unit="$plugin_root/systemd/omarchy-audio-speaker-discovery.service"
readonly unit_dir="$HOME/.config/systemd/user"
readonly target_unit="$unit_dir/omarchy-audio-speaker-discovery.service"
readonly raop_source="/usr/share/pipewire/pipewire.conf.avail/50-raop.conf"
readonly raop_config_dir="$HOME/.config/pipewire/pipewire.conf.d"
readonly raop_config="$raop_config_dir/50-omarchy-raop.conf"

missing=()
for command in avahi-browse ffmpeg ip jq pactl pw-cli pw-dump python3 systemctl systemd-run; do
  command -v "$command" >/dev/null 2>&1 || missing+=("$command")
done
python3 -c 'import pychromecast' >/dev/null 2>&1 || missing+=("python-pychromecast")
[[ -e $raop_source ]] || missing+=("pipewire-zeroconf")
if ((${#missing[@]} > 0)); then
  printf 'Missing Wi-Fi speaker dependencies: %s\n' "${missing[*]}" >&2
  printf 'Install the packages listed in README.md, then rerun setup.sh.\n' >&2
  exit 1
fi

if [[ ${1:-} == --check ]]; then
  systemctl --user is-active --quiet omarchy-audio-speaker-discovery.service
  [[ -e $raop_config ]]
  "$plugin_root/scripts/audio-output" current --json | jq -e '.kind' >/dev/null
  printf 'Audio + Wi-Fi setup is healthy.\n'
  exit 0
fi

if [[ $(realpath -m "$plugin_root") != $(realpath -m "$installed_root") ]]; then
  printf 'Run setup from the installed plugin: %s/setup.sh\n' "$installed_root" >&2
  exit 1
fi

raop_added=0
install -d -m 700 "$raop_config_dir"
if [[ ! -e $raop_config && ! -L $raop_config ]]; then
  ln -s "$raop_source" "$raop_config"
  raop_added=1
elif [[ ! -L $raop_config || $(readlink -f "$raop_config") != $(readlink -f "$raop_source") ]]; then
  printf 'Keeping existing PipeWire config: %s\n' "$raop_config"
fi

install -d -m 700 "$unit_dir"
if [[ -e $target_unit || -L $target_unit ]]; then
  if [[ ! -L $target_unit || $(readlink -f "$target_unit") != $(readlink -f "$source_unit") ]]; then
    printf 'Refusing to replace unrelated service file: %s\n' "$target_unit" >&2
    exit 1
  fi
else
  ln -s "$source_unit" "$target_unit"
fi

systemctl --user daemon-reload
systemctl --user enable --now omarchy-audio-speaker-discovery.service
if ((raop_added)); then
  omarchy-restart-audio
fi
printf 'Audio + Wi-Fi discovery service enabled.\n'
