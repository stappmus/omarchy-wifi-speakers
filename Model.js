function isPlaybackStream(node) {
  if (!node || !node.isStream) return false
  if (node.isSink === true) return true

  var mediaClass = String(node.type || "")
  return mediaClass.indexOf("Stream/Output/Audio") !== -1
    || mediaClass.indexOf("AudioOutStream") !== -1
    || mediaClass.indexOf("Output") !== -1
}

function isAudioSource(node) {
  if (!node) return false
  if (node.audio) return true

  var mediaClass = String(node.type || "")
  return mediaClass.indexOf("Audio/Source") !== -1
    || mediaClass.indexOf("AudioSource") !== -1
    || mediaClass.indexOf("Source") !== -1
}

function listSnapshot(list) {
  var snapshot = []
  if (!list || typeof list.length !== "number") return snapshot
  for (var i = 0; i < list.length; i++) snapshot.push(list[i])
  return snapshot
}

function outputVolumeName(volume, muted) {
  if (muted) return "Muted"
  var p = Math.round(volume * 100)
  if (p === 0) return "Silenced"
  if (p >= 100) return "Concert hall"
  if (p >= 85) return "Party mode"
  if (p >= 70) return "Cranked up"
  if (p >= 50) return "Steady groove"
  if (p >= 30) return "Easy listening"
  if (p >= 15) return "Murmur"
  return "Whisper"
}

function parseSinkAvailability(raw) {
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    if (parts.length >= 2) next[parts[0]] = parts[1] !== "0"
  }
  return next
}

function friendlyDeviceLabel(text) {
  var label = String(text || "").trim()
  label = label.replace(/^sof-soundwire\s+/i, "")
  label = label.replace(/^built-?in audio\s+/i, "")
  label = label.replace(/\s+Output$/i, "")
  label = label.replace(/\s+Input$/i, "")
  label = label.replace(/\bMicrophones\b/g, "Microphone")
  return label
}

function nodeProps(node) {
  return node && node.ready && node.properties ? node.properties : {}
}

function nodeLabel(node) {
  if (!node) return "Unknown"
  var p = nodeProps(node)
  var nickname = friendlyDeviceLabel(node.nickname || node.nick || p["node.nick"] || p["device.profile.description"] || "")
  if (nickname) return nickname
  return friendlyDeviceLabel(node.description || p["node.description"] || node.name || "Unknown")
}

function isAirPlaySink(node) {
  if (!node) return false
  var p = nodeProps(node)
  var name = String(node.name || p["node.name"] || "").toLowerCase()
  var api = String(p["device.api"] || "").toLowerCase()
  return name === "raop_sink"
    || name.indexOf("raop_sink.") === 0
    || api === "raop"
}

function nativeSinkMatchesSpeaker(node, speaker) {
  if (!isAirPlaySink(node) || !speaker) return false
  var p = nodeProps(node)
  var blob = String([
    node.name, node.description, node.nickname, node.nick,
    p["node.name"] || "",
    p["node.description"] || "",
    p["device.description"] || "",
    p["raop.hostname"] || "",
    p["raop.name"] || ""
  ].join(" ")).toLowerCase()
  var address = String(speaker.address || "").trim().toLowerCase()
  var host = String(speaker.host || "").trim().toLowerCase().replace(/\.$/, "")
  if (address && blob.indexOf(address) !== -1) return true
  if (host && blob.indexOf(host) !== -1) return true

  var speakerLabel = friendlyDeviceLabel(speaker.label || "").toLowerCase()
  var sinkLabel = nodeLabel(node).toLowerCase()
  return speakerLabel !== "" && speakerLabel === sinkLabel
}

function speakersShareReceiver(first, second) {
  if (!first || !second) return false
  var firstAddress = String(first.address || "").trim().toLowerCase()
  var secondAddress = String(second.address || "").trim().toLowerCase()
  if (firstAddress && secondAddress) return firstAddress === secondAddress

  var firstHost = String(first.host || "").trim().toLowerCase().replace(/\.$/, "")
  var secondHost = String(second.host || "").trim().toLowerCase().replace(/\.$/, "")
  if (firstHost && secondHost) return firstHost === secondHost

  var firstLabel = friendlyDeviceLabel(first.label || "").toLowerCase()
  var secondLabel = friendlyDeviceLabel(second.label || "").toLowerCase()
  return firstLabel !== "" && firstLabel === secondLabel
}

function filterWifiSpeakers(speakers, sinks) {
  var values = Array.isArray(speakers) ? speakers : []
  var nativeSinks = Array.isArray(sinks) ? sinks : []
  var filtered = []
  for (var i = 0; i < values.length; i++) {
    var speaker = values[i]
    var protocol = String(speaker && speaker.protocol || "").toLowerCase()
    if (!speaker || (protocol !== "cast" && protocol !== "raop")) continue
    if (protocol === "cast") {
      filtered.push(speaker)
      continue
    }
    var represented = false
    for (var castIndex = 0; castIndex < values.length; castIndex++) {
      var castSpeaker = values[castIndex]
      if (String(castSpeaker && castSpeaker.protocol || "").toLowerCase() === "cast"
          && speakersShareReceiver(speaker, castSpeaker)) {
        represented = true
        break
      }
    }
    for (var j = 0; j < nativeSinks.length; j++) {
      if (represented) break
      if (nativeSinkMatchesSpeaker(nativeSinks[j], speaker)) {
        represented = true
        break
      }
    }
    if (!represented) filtered.push(speaker)
  }
  return filtered
}

function castSpeakerForNativeSink(speakers, node) {
  var values = Array.isArray(speakers) ? speakers : []
  for (var i = 0; i < values.length; i++) {
    var speaker = values[i]
    if (String(speaker && speaker.protocol || "").toLowerCase() === "cast"
        && nativeSinkMatchesSpeaker(node, speaker)) return speaker
  }
  return null
}

function wifiSpeakerKey(speaker) {
  if (!speaker || !speaker.speakerId) return ""
  return String(speaker.protocol || "cast").toLowerCase()
    + ":" + String(speaker.speakerId)
}

function rememberCastSpeakers(speakers, remembered) {
  var current = Array.isArray(speakers) ? speakers : []
  var previous = Array.isArray(remembered) ? remembered : []
  var result = []
  var indexes = {}

  function add(speaker) {
    if (String(speaker && speaker.protocol || "").toLowerCase() !== "cast") return
    var key = wifiSpeakerKey(speaker)
    if (!key) return
    if (indexes[key] !== undefined) result[indexes[key]] = speaker
    else {
      indexes[key] = result.length
      result.push(speaker)
    }
  }

  for (var i = 0; i < previous.length; i++) add(previous[i])
  for (var j = 0; j < current.length; j++) add(current[j])
  return result
}

function rememberedCastReconnectKeys(speakers, remembered, nodes) {
  var current = Array.isArray(speakers) ? speakers : []
  var previous = Array.isArray(remembered) ? remembered : []
  // Quickshell exposes Pipewire.nodes.values as an indexable list, not a real
  // JavaScript Array. Copy it before matching so reconnect protection also runs
  // in the live shell rather than only in Node-based tests.
  var nativeSinks = listSnapshot(nodes)
  var present = {}
  var keys = []

  for (var i = 0; i < current.length; i++) {
    var currentKey = wifiSpeakerKey(current[i])
    if (currentKey) present[currentKey] = true
  }

  for (var j = 0; j < previous.length; j++) {
    var speaker = previous[j]
    var key = wifiSpeakerKey(speaker)
    if (!key || present[key]) continue
    for (var k = 0; k < nativeSinks.length; k++) {
      var node = nativeSinks[k]
      var name = String(node && node.name || "")
      if (name.indexOf("raop_sink.stappmus_wifi_") === 0) continue
      if (nativeSinkMatchesSpeaker(node, speaker)) {
        keys.push(key)
        break
      }
    }
  }
  return keys
}

function wifiSpeakerCandidates(speakers, remembered, nodes, includeRemembered) {
  var current = Array.isArray(speakers) ? speakers : []
  var previous = Array.isArray(remembered) ? remembered : []
  var reconnecting = rememberedCastReconnectKeys(current, previous, nodes)
  var reconnectingSet = {}
  var result = current.slice()

  if (includeRemembered === false) return result
  for (var i = 0; i < reconnecting.length; i++) reconnectingSet[reconnecting[i]] = true
  for (var j = 0; j < previous.length; j++) {
    var speaker = previous[j]
    var key = wifiSpeakerKey(speaker)
    if (!reconnectingSet[key]) continue
    var placeholder = {}
    for (var field in speaker) placeholder[field] = speaker[field]
    placeholder.available = false
    placeholder.reconnecting = true
    result.push(placeholder)
  }
  return result
}

function wifiSinkName(speakerId, protocol) {
  var id = String(speakerId || "").replace(/[^A-Za-z0-9]/g, "").toLowerCase()
  if (!id) return ""
  return String(protocol || "").toLowerCase() === "raop"
    ? "raop_sink.stappmus_wifi_" + id
    : "omarchy_wifi_cast_" + id
}

function isHeadphones(node) {
  if (!node) return false
  var p = nodeProps(node)
  var blob = String([
    node.name, node.description, node.nickname,
    p["device.icon-name"] || "",
    p["device.product.name"] || "",
    p["node.description"] || "",
    p["node.nick"] || ""
  ].join(" ")).toLowerCase()
  return blob.indexOf("headphone") !== -1
    || blob.indexOf("headset") !== -1
    || blob.indexOf("earbud") !== -1
    || blob.indexOf("earphone") !== -1
    || blob.indexOf("airpod") !== -1
}

function sinkGlyph(node) {
  if (!node) return "󰓃"
  if (isHeadphones(node)) return "󰋋"
  var p = nodeProps(node)
  var blob = String([
    node.name, node.description, node.nickname,
    p["device.icon-name"] || "",
    p["device.product.name"] || ""
  ].join(" ")).toLowerCase()
  if (blob.indexOf("bluetooth") !== -1) return "󰂯"
  if (blob.indexOf("hdmi") !== -1 || blob.indexOf("display") !== -1) return "󰍹"
  return "󰓃"
}

function sourceGlyph(node) {
  if (!node) return "󰍬"
  var p = nodeProps(node)
  var blob = String([
    node.name, node.description, node.nickname,
    p["device.icon-name"] || ""
  ].join(" ")).toLowerCase()
  if (blob.indexOf("headset") !== -1) return "󰋋"
  if (blob.indexOf("bluetooth") !== -1) return "󰂯"
  if (blob.indexOf("webcam") !== -1 || blob.indexOf("camera") !== -1) return "󰄀"
  return "󰍬"
}

function friendlyStreamLabel(label) {
  label = String(label || "").trim()
  if (!label) return ""

  var known = {
    "spotify": "Spotify"
  }
  var normalized = label.toLowerCase()
  return known[normalized] || label
}

function streamLabelKey(label) {
  return String(label || "").trim().toLowerCase()
}

function streamLabelIsGeneric(label) {
  return streamLabelKey(label) === "audio-src"
}

function rawStreamLabel(node) {
  if (!node) return ""
  var p = nodeProps(node)
  return p["application.name"]
    || node.description
    || p["media.name"]
    || p["node.name"]
    || node.name
}

function mprisPlayerLabel(player) {
  if (!player) return ""
  return friendlyStreamLabel(player.identity || player.desktopEntry || "")
}

function mprisPlayerIsProxy(player) {
  var dbusName = String(player && player.dbusName || "").toLowerCase()
  var desktopEntry = String(player && player.desktopEntry || "").toLowerCase()
  return dbusName.indexOf("playerctld") !== -1 || desktopEntry === "playerctld"
}

function streamRepresentsMprisPlayer(streamLabel, playerLabel) {
  var streamKey = streamLabelKey(friendlyStreamLabel(streamLabel))
  var playerKey = streamLabelKey(playerLabel)
  if (!streamKey || !playerKey) return false
  return streamKey === playerKey
    || streamKey.indexOf(playerKey) !== -1
    || playerKey.indexOf(streamKey) !== -1
}

function mprisLabelsFor(players, predicate) {
  var values = Array.isArray(players) ? players : []
  var playingCandidates = []
  var candidates = []
  var playingProxyCandidates = []
  var proxyCandidates = []

  for (var i = 0; i < values.length; i++) {
    var player = values[i]
    if (!player) continue
    if (!player.isPlaying && !player.canPlay) continue

    var playerLabel = mprisPlayerLabel(player)
    if (!playerLabel || !predicate(playerLabel)) continue

    if (mprisPlayerIsProxy(player)) {
      if (player.isPlaying) playingProxyCandidates.push(playerLabel)
      proxyCandidates.push(playerLabel)
    } else {
      if (player.isPlaying) playingCandidates.push(playerLabel)
      candidates.push(playerLabel)
    }
  }

  if (playingCandidates.length === 1) return playingCandidates[0]
  if (playingCandidates.length === 0 && playingProxyCandidates.length === 1) return playingProxyCandidates[0]
  if (candidates.length === 1) return candidates[0]
  if (candidates.length === 0 && proxyCandidates.length === 1) return proxyCandidates[0]
  return ""
}

function matchingMprisStreamLabel(label, players) {
  if (streamLabelIsGeneric(label)) return ""
  return mprisLabelsFor(players, function(playerLabel) {
    return streamRepresentsMprisPlayer(label, playerLabel)
  })
}

function unmatchedMprisStreamLabel(label, players, streams) {
  if (!streamLabelIsGeneric(label)) return ""

  return mprisLabelsFor(players, function(playerLabel) {
    var values = Array.isArray(streams) ? streams : []
    for (var i = 0; i < values.length; i++) {
      var stream = values[i]
      var streamLabel = rawStreamLabel(stream)
      if (!streamLabelIsGeneric(streamLabel) && streamRepresentsMprisPlayer(streamLabel, playerLabel))
        return false
    }
    return true
  })
}

function streamLabel(node, players, streams) {
  if (!node) return "Stream"
  var label = rawStreamLabel(node)
  return friendlyStreamLabel(matchingMprisStreamLabel(label, players)
    || unmatchedMprisStreamLabel(label, players, streams)
    || label) || "Stream"
}

function streamRepresentsPlayer(node, player, players, streams) {
  if (!node || !player) return false
  var playerLabel = mprisPlayerLabel(player)
  if (!playerLabel) return false

  var label = rawStreamLabel(node)
  if (!streamLabelIsGeneric(label)) return streamRepresentsMprisPlayer(label, playerLabel)
  return streamRepresentsMprisPlayer(streamLabel(node, players, streams), playerLabel)
}

if (typeof module !== "undefined") {
  module.exports = {
    isPlaybackStream: isPlaybackStream,
    isAudioSource: isAudioSource,
    listSnapshot: listSnapshot,
    outputVolumeName: outputVolumeName,
    parseSinkAvailability: parseSinkAvailability,
    friendlyDeviceLabel: friendlyDeviceLabel,
    nodeProps: nodeProps,
    nodeLabel: nodeLabel,
    isAirPlaySink: isAirPlaySink,
    nativeSinkMatchesSpeaker: nativeSinkMatchesSpeaker,
    speakersShareReceiver: speakersShareReceiver,
    filterWifiSpeakers: filterWifiSpeakers,
    castSpeakerForNativeSink: castSpeakerForNativeSink,
    wifiSpeakerKey: wifiSpeakerKey,
    rememberCastSpeakers: rememberCastSpeakers,
    rememberedCastReconnectKeys: rememberedCastReconnectKeys,
    wifiSpeakerCandidates: wifiSpeakerCandidates,
    wifiSinkName: wifiSinkName,
    isHeadphones: isHeadphones,
    sinkGlyph: sinkGlyph,
    sourceGlyph: sourceGlyph,
    friendlyStreamLabel: friendlyStreamLabel,
    streamLabelKey: streamLabelKey,
    streamLabelIsGeneric: streamLabelIsGeneric,
    rawStreamLabel: rawStreamLabel,
    mprisPlayerLabel: mprisPlayerLabel,
    mprisPlayerIsProxy: mprisPlayerIsProxy,
    streamRepresentsMprisPlayer: streamRepresentsMprisPlayer,
    mprisLabelsFor: mprisLabelsFor,
    matchingMprisStreamLabel: matchingMprisStreamLabel,
    unmatchedMprisStreamLabel: unmatchedMprisStreamLabel,
    streamLabel: streamLabel,
    streamRepresentsPlayer: streamRepresentsPlayer
  }
}
