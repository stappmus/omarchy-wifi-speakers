# Audio + Wi-Fi for Omarchy Quattro

Omarchy's Audio bar widget with network outputs built into the ordinary Audio
panel. AirPlay receivers use PipeWire's native RAOP support. Google Cast is
available as a managed fallback when the same receiver is not already exposed
as an AirPlay sink.

There is no standalone speaker chooser.

![Omarchy Audio panel showing a network receiver beside the laptop output](preview.png)

The plugin is a clone replacement for `omarchy.audio`, so the existing volume
icon, `SUPER + CTRL + A`, and `omarchy-shell shell toggle omarchy.audio` all
open this panel.

## Install

```bash
omarchy pkg add avahi ffmpeg iproute2 jq pipewire-pulse pipewire-zeroconf python-pychromecast
omarchy plugin add https://github.com/stappmus/omarchy-wifi-speakers.git --enable
~/.config/omarchy/plugins/stappmus.audio/setup.sh
```

The setup command enables native RAOP discovery and links the included user
service for Cast/AirPlay discovery. It preserves unrelated PipeWire and systemd
files instead of replacing them.

If UFW is active, allow only private-network receivers to reach the streaming
ports used by Cast and AirPlay:

```bash
sudo ufw allow proto tcp from 10.0.0.0/8 to any port 49785 comment allow-stappmus-cast-audio
sudo ufw allow proto tcp from 172.16.0.0/12 to any port 49785 comment allow-stappmus-cast-audio
sudo ufw allow proto tcp from 192.168.0.0/16 to any port 49785 comment allow-stappmus-cast-audio
sudo ufw allow proto udp from 10.0.0.0/8 to any port 6001:6129 comment allow-stappmus-airplay-audio
sudo ufw allow proto udp from 172.16.0.0/12 to any port 6001:6129 comment allow-stappmus-airplay-audio
sudo ufw allow proto udp from 192.168.0.0/16 to any port 6001:6129 comment allow-stappmus-airplay-audio
```

### Migrating from the 1.0 standalone selector

```bash
systemctl --user disable --now omarchy-audio-speaker-discovery.service
unit=~/.config/systemd/user/omarchy-audio-speaker-discovery.service
[[ -L $unit ]] && unlink "$unit"
systemctl --user daemon-reload
omarchy plugin remove stappmus.wifi-speakers
omarchy plugin add https://github.com/stappmus/omarchy-wifi-speakers.git --enable
~/.config/omarchy/plugins/stappmus.audio/setup.sh
```

Remove any old `SUPER + XF86AudioMute` selector binding. The Audio panel's
standard shortcut is `SUPER + CTRL + A`. To keep the hardware volume keys
synchronized with a Cast receiver, copy
[`extras/wifi-speakers.lua`](extras/wifi-speakers.lua) into `~/.config/hypr/`,
add `require("hypr.wifi-speakers")` to `~/.config/hypr/bindings.lua`, and run
`hyprctl reload`. That module contains volume bindings only.

## How routing works

- Native AirPlay sinks stay ordinary PipeWire outputs and appear once in the
  Audio panel. A matching Cast discovery record is suppressed to avoid showing
  the same receiver twice.
- Cast creates a temporary null sink, moves real application streams to it,
  and serves the monitor only to the selected receiver on TCP port 49785.
- Receiver volume is controlled through a local Unix socket. Selecting a local
  output cancels and removes the network route before switching sinks.
- The discovery service writes one atomic cache; the Audio panel watches that
  file instead of running network scans in its UI process.
- Disconnecting restores the exact output that was active before the network
  route. No EasyEffects sink name or other fixed DSP graph is assumed.

Runtime state and control sockets live under the user's runtime directory.

## CLI

```bash
plugin=~/.config/omarchy/plugins/stappmus.audio
$plugin/scripts/audio-output list --json
$plugin/scripts/audio-output current --json
$plugin/scripts/audio-output connect SPEAKER_ID cast
$plugin/scripts/audio-output internal
$plugin/scripts/audio-output volume raise
```

## Remove

```bash
~/.config/omarchy/plugins/stappmus.audio/scripts/audio-output internal
systemctl --user disable --now omarchy-audio-speaker-discovery.service
unit=~/.config/systemd/user/omarchy-audio-speaker-discovery.service
[[ -L $unit ]] && unlink "$unit"
systemctl --user daemon-reload
omarchy plugin remove stappmus.audio
```

Removing this clone restores Omarchy's built-in `omarchy.audio` widget.

## Test

```bash
./test/run.sh
omarchy plugin validate .
```

The mock route tests do not modify the host's real PipeWire graph. A physical
receiver is still required for a complete end-to-end Cast or AirPlay test.

Licensed under the MIT License.
