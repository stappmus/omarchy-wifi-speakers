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

assert.equal(Model.isAirPlaySink(airPlaySink), true)
assert.equal(Model.isAirPlaySink(localSink), false)
assert.equal(Model.nativeSinkMatchesSpeaker(airPlaySink, matchingCast), true)
assert.deepEqual(Model.filterWifiSpeakers([matchingCast, otherCast], [airPlaySink]), [otherCast])
assert.deepEqual(Model.filterWifiSpeakers([matchingCast], [localSink]), [matchingCast])
assert.equal(Model.wifiSinkName("AB-CD", "cast"), "omarchy_wifi_cast_abcd")
assert.equal(Model.wifiSinkName("AB-CD", "raop"), "raop_sink.stappmus_wifi_abcd")

console.log("ok - native AirPlay sinks deduplicate matching Wi-Fi discovery rows")
