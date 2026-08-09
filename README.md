# Wi-Fi Audio for Omarchy Quattro

Bring AirPlay and Google Cast speakers into Omarchy's Audio panel. Network
speakers appear alongside your laptop speakers, headphones, and HDMI outputs,
so switching rooms or devices feels like using any other audio output.

![Omarchy Audio panel showing a Wi-Fi receiver beside the laptop output](preview.png)

## What you get

- AirPlay outputs through PipeWire's native RAOP support.
- Google Cast outputs directly in the Audio panel.
- Automatic discovery on your local network.
- One entry per receiver when a device supports both AirPlay and Cast.
- Volume, microphone, and per-application controls from Omarchy's regular Audio
  widget.
- Automatic restoration of your previous output when leaving a Cast route.
- Compatibility with speaker tuning, headphones, HDMI, and unprocessed
  PipeWire outputs—no fixed EasyEffects sink required.

The plugin replaces the stock `omarchy.audio` widget with an extended version
in the same bar position. Removing it restores the stock widget.

## Requirements

- Omarchy Quattro with the Quickshell-based bar.
- An AirPlay or Google Cast receiver reachable on the same local network.
- Avahi/mDNS available on that network.

## Install

Install the runtime packages:

```bash
omarchy pkg add avahi ffmpeg iproute2 jq pipewire-pulse pipewire-zeroconf python-pychromecast
```

Add and enable the plugin:

```bash
omarchy plugin add https://github.com/stappmus/omarchy-wifi-speakers.git --enable
~/.config/omarchy/plugins/stappmus.audio/setup.sh
```

The setup command enables native AirPlay discovery and starts the included
user service that maintains the receiver cache. It will not replace unrelated
PipeWire configuration or systemd units.

## Use it

Open Audio by clicking the volume icon or pressing `SUPER + CTRL + A`. Available
receivers appear in the **Output** list:

- AirPlay receivers behave like normal PipeWire outputs.
- Cast-only receivers appear with a **Google Cast** subtitle.
- Selecting a local output ends the active network route and returns playback
  to that device.

The panel can also be opened from a terminal:

```bash
omarchy-shell shell toggle omarchy.audio
```

### Keep hardware volume keys synchronized with Cast

The panel controls Cast receiver volume directly. To give the media keys the
same route-aware behavior, copy
[`extras/wifi-speakers.lua`](extras/wifi-speakers.lua) to
`~/.config/hypr/wifi-speakers.lua`:

```bash
cp ~/.config/omarchy/plugins/stappmus.audio/extras/wifi-speakers.lua ~/.config/hypr/wifi-speakers.lua
```

Then add this line to `~/.config/hypr/bindings.lua`:

```lua
require("hypr.wifi-speakers")
```

Apply the binding change:

```bash
hyprctl reload
```

The optional module only replaces the normal and precise volume bindings.

## Firewall

Cast streams from TCP port `49785`. AirPlay uses UDP ports `6001–6129` for
control and timing callbacks. If UFW is enabled, allow those ports only from
private networks:

```bash
sudo ufw allow proto tcp from 10.0.0.0/8 to any port 49785 comment allow-stappmus-cast-audio
sudo ufw allow proto tcp from 172.16.0.0/12 to any port 49785 comment allow-stappmus-cast-audio
sudo ufw allow proto tcp from 192.168.0.0/16 to any port 49785 comment allow-stappmus-cast-audio
sudo ufw allow proto udp from 10.0.0.0/8 to any port 6001:6129 comment allow-stappmus-airplay-audio
sudo ufw allow proto udp from 172.16.0.0/12 to any port 6001:6129 comment allow-stappmus-airplay-audio
sudo ufw allow proto udp from 192.168.0.0/16 to any port 6001:6129 comment allow-stappmus-airplay-audio
```

## How Cast routing works

The discovery service writes an atomic cache outside the shell process. The
Audio panel watches that cache instead of scanning the network itself.

When you choose a Cast receiver, the plugin creates a temporary PipeWire sink,
moves real application streams to it, and serves the sink monitor only to the
selected receiver. Volume commands travel over a local Unix socket. Returning
to a local output removes the temporary route and restores the exact output
that was active before it.

Runtime state, control sockets, and the receiver cache live under the user's
runtime directory.

## Troubleshooting

Check the installation and discovery service:

```bash
~/.config/omarchy/plugins/stappmus.audio/setup.sh --check
systemctl --user status omarchy-audio-speaker-discovery.service
```

Inspect discovered receivers and the current route:

```bash
plugin=~/.config/omarchy/plugins/stappmus.audio
$plugin/scripts/audio-output list --json
$plugin/scripts/audio-output current --json
```

If discovery is empty, confirm that the computer and receiver are on the same
network and that multicast DNS is not blocked by client isolation or firewall
rules.

## Command line

```bash
plugin=~/.config/omarchy/plugins/stappmus.audio
$plugin/scripts/audio-output connect SPEAKER_ID cast
$plugin/scripts/audio-output internal
$plugin/scripts/audio-output volume raise
```

## Uninstall

End any managed route, disable discovery, and remove the plugin:

```bash
~/.config/omarchy/plugins/stappmus.audio/scripts/audio-output internal
systemctl --user disable --now omarchy-audio-speaker-discovery.service
unit=~/.config/systemd/user/omarchy-audio-speaker-discovery.service
[[ -L $unit ]] && unlink "$unit"
systemctl --user daemon-reload
omarchy plugin remove stappmus.audio
```

If you enabled the optional volume bindings, remove
`require("hypr.wifi-speakers")` from `~/.config/hypr/bindings.lua`, remove the
copied module, and run `hyprctl reload`. Omarchy will restore its built-in Audio
widget when the plugin is removed.

<details>
<summary>Upgrading from version 1.0</summary>

Version 1.1 uses the plugin ID `stappmus.audio` so it can replace Omarchy's
Audio widget. Remove the earlier installation before adding the current one:

```bash
old=~/.config/omarchy/plugins/stappmus.wifi-speakers
[[ -x "$old/scripts/audio-output" ]] && "$old/scripts/audio-output" internal
systemctl --user disable --now omarchy-audio-speaker-discovery.service
unit=~/.config/systemd/user/omarchy-audio-speaker-discovery.service
[[ -L $unit ]] && unlink "$unit"
systemctl --user daemon-reload
omarchy plugin remove stappmus.wifi-speakers
omarchy plugin add https://github.com/stappmus/omarchy-wifi-speakers.git --enable
~/.config/omarchy/plugins/stappmus.audio/setup.sh
```

Remove any earlier custom speaker-selector binding. The Audio panel shortcut is
`SUPER + CTRL + A`.

</details>

## Development

```bash
./test/run.sh
omarchy plugin validate .
```

The automated route tests use mocks and do not modify the host PipeWire graph.
A physical receiver is still required for a complete end-to-end test.

Licensed under the MIT License.
