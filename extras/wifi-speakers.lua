-- Optional selector and route-aware volume bindings for Omarchy Quattro.

local user_home = os.getenv("HOME") or ""
local plugin = user_home .. "/.config/omarchy/plugins/stappmus.wifi-speakers"
local selector = plugin .. "/scripts/open-overlay"
local audio = plugin .. "/scripts/audio-output"

hl.unbind("SUPER + XF86AudioMute")
hl.unbind("XF86AudioRaiseVolume")
hl.unbind("XF86AudioLowerVolume")
hl.unbind("XF86AudioMute")
hl.unbind("ALT + XF86AudioRaiseVolume")
hl.unbind("ALT + XF86AudioLowerVolume")

o.bind("SUPER + XF86AudioMute", "Choose Wi-Fi speaker", selector, { locked = true })
o.bind("XF86AudioRaiseVolume", "Volume up", audio .. " volume raise", { locked = true, repeating = true })
o.bind("XF86AudioLowerVolume", "Volume down", audio .. " volume lower", { locked = true, repeating = true })
o.bind("XF86AudioMute", "Mute", audio .. " volume mute-toggle", { locked = true })
o.bind("ALT + XF86AudioRaiseVolume", "Volume up precise", audio .. " volume +1", { locked = true, repeating = true })
o.bind("ALT + XF86AudioLowerVolume", "Volume down precise", audio .. " volume -1", { locked = true, repeating = true })
