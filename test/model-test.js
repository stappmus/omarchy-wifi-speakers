const assert = require("node:assert/strict")
const Model = require("../Model.js")

const airPlaySink = {
  ready: true,
  name: "raop_sink.audiocast.local.192.168.50.118.7000",
  description: "Lyd på fuggeln",
  properties: {
    "node.name": "raop_sink.audiocast.local.192.168.50.118.7000",
    "device.description": "Lyd på fuggeln"
  }
}
const localSink = {
  ready: true,
  name: "alsa_output.speaker",
  description: "Lyd på fuggeln",
  properties: { "device.api": "alsa" }
}
const matchingCast = {
  speakerId: "cast-id",
  label: "Lyd på fuggeln",
  protocol: "cast",
  address: "192.168.50.118"
}
const otherCast = {
  speakerId: "other-id",
  label: "Office",
  protocol: "cast",
  address: "192.168.50.120"
}
const matchingAirPlay = {
  speakerId: "airplay-id",
  label: "Lyd på fuggeln",
  protocol: "raop",
  address: "192.168.50.118"
}

assert.equal(Model.isAirPlaySink(airPlaySink), true)
assert.equal(Model.isAirPlaySink(localSink), false)
assert.equal(Model.nativeSinkMatchesSpeaker(airPlaySink, matchingCast), true)
assert.deepEqual(Model.filterWifiSpeakers([matchingCast, otherCast], [airPlaySink]), [matchingCast, otherCast])
assert.equal(Model.speakersShareReceiver(matchingAirPlay, matchingCast), true)
assert.equal(Model.speakersShareReceiver(matchingAirPlay, {...matchingCast, address: "192.168.50.119"}), false)
assert.deepEqual(Model.filterWifiSpeakers([matchingAirPlay, matchingCast], []), [matchingCast])
assert.deepEqual(Model.filterWifiSpeakers([matchingAirPlay], [airPlaySink]), [])
assert.deepEqual(Model.filterWifiSpeakers([matchingCast], [localSink]), [matchingCast])
assert.equal(Model.castSpeakerForNativeSink([matchingCast, otherCast], airPlaySink), matchingCast)
assert.equal(Model.castSpeakerForNativeSink([otherCast], airPlaySink), null)
const remembered = Model.rememberCastSpeakers([matchingCast], [otherCast])
assert.deepEqual(remembered, [otherCast, matchingCast])
assert.deepEqual(
  Model.rememberedCastReconnectKeys([], remembered, [airPlaySink]),
  ["cast:cast-id"]
)
const reconnecting = Model.wifiSpeakerCandidates([], remembered, [airPlaySink], true)
assert.equal(reconnecting.length, 1)
assert.equal(reconnecting[0].speakerId, matchingCast.speakerId)
assert.equal(reconnecting[0].available, false)
assert.equal(reconnecting[0].reconnecting, true)
const transientDualProtocol = Model.wifiSpeakerCandidates(
  [matchingAirPlay],
  remembered,
  [airPlaySink],
  true
)
assert.deepEqual(
  Model.filterWifiSpeakers(transientDualProtocol, []),
  [transientDualProtocol[1]]
)
assert.deepEqual(
  Model.wifiSpeakerCandidates([], remembered, [airPlaySink], false),
  []
)
assert.deepEqual(
  Model.filterWifiSpeakers(
    Model.wifiSpeakerCandidates([matchingAirPlay], remembered, [airPlaySink], false),
    [airPlaySink]
  ),
  []
)
assert.deepEqual(
  Model.wifiSpeakerCandidates([matchingCast], remembered, [airPlaySink], true),
  [matchingCast]
)
assert.equal(Model.wifiSinkName("AB-CD", "cast"), "omarchy_wifi_cast_abcd")
assert.equal(Model.wifiSinkName("AB-CD", "raop"), "raop_sink.stappmus_wifi_abcd")

console.log("ok - dual-protocol receivers stay stable across Wi-Fi reconnects")
