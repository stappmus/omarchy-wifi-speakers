#!/usr/bin/python3

import importlib.machinery
import importlib.util
import io
import os
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parent.parent


def load_module(name, path):
  loader = importlib.machinery.SourceFileLoader(name, str(path))
  spec = importlib.util.spec_from_loader(loader.name, loader)
  module = importlib.util.module_from_spec(spec)
  sys.modules[name] = module
  loader.exec_module(module)
  return module


discovery = load_module("speaker_discovery", ROOT / "scripts/speaker-discovery")
stream = load_module("cast_stream", ROOT / "scripts/cast-stream")
volume = load_module("cast_volume", ROOT / "scripts/cast-volume")


class WifiSpeakerTest(unittest.TestCase):
  def test_discovery_parses_cast_and_airplay(self):
    cast_fields = (
      r'=;wlan0;IPv4;Living\032Room;_googlecast._tcp;local;living.local;192.168.1.20;8009;'
      r'"id=12345678-1234-1234-1234-123456789abc" "fn=Living\032Room" "md=Nest\032Audio"'
    ).split(";", 9)
    cast = discovery.speaker_from_fields(cast_fields)
    self.assertEqual(cast.speaker_id, "12345678-1234-1234-1234-123456789abc")
    self.assertEqual(cast.label, "Living Room")
    self.assertEqual(cast.model, "Nest Audio")

    airplay_fields = (
      r'=;wlan0;IPv4;AABBCC@Kitchen;_raop._tcp;local;kitchen.local;192.168.1.21;7000;'
      r'"tp=UDP,TCP" "et=0,1" "cn=0,1" "am=AudioAccessory"'
    ).split(";", 9)
    airplay = discovery.speaker_from_fields(airplay_fields)
    self.assertEqual(airplay.protocol, "raop")
    self.assertEqual(airplay.transport, "udp")
    self.assertEqual(airplay.encryption_codec, "RSA:PCM")

  def test_discovery_coalesces_events_and_unchanged_publications(self):
    fields = (
      r'=;wlan0;IPv4;Office;_googlecast._tcp;local;office.local;192.168.1.30;8009;'
      r'"id=office-id" "fn=Office" "md=Nest Audio"'
    ).split(";", 9)
    key = discovery.service_key(fields)
    records = {}
    self.assertTrue(discovery.apply_browser_event(";".join(fields), records))
    self.assertFalse(discovery.apply_browser_event(";".join(fields), records))
    self.assertTrue(discovery.apply_browser_event("-;" + ";".join(fields[1:]), records))
    self.assertEqual(records, {})

    with tempfile.TemporaryDirectory() as temporary:
      cache = Path(temporary)
      discovery.CACHE_FILE = cache / "speakers.tsv"
      discovery.STATUS_FILE = cache / "status"
      discovery.SNAPSHOT_FILE = cache / "snapshot.json"
      for path in (discovery.CACHE_FILE, discovery.STATUS_FILE, discovery.SNAPSHOT_FILE):
        path.touch()
      discovery.published_status = "ready"
      discovery.published_speakers = []
      writes = []
      original_atomic_write = discovery.atomic_write
      discovery.atomic_write = lambda path, contents: writes.append((path, contents))
      try:
        discovery.publish_status("ready")
        discovery.publish_speakers({})
      finally:
        discovery.atomic_write = original_atomic_write
      self.assertEqual(writes, [])

  def test_cast_stream_formats_client_filter_and_volume_protocol(self):
    self.assertEqual(
      [item.content_type for item in stream.AUDIO_FORMATS],
      ["audio/wav", "audio/mpeg"],
    )
    self.assertEqual(stream.fallback_format_index(0, False), 1)
    self.assertIsNone(stream.fallback_format_index(0, True))

    target = stream.StreamTarget(stream.AUDIO_FORMATS[0], "127.0.0.1")
    self.assertTrue(target.allows("127.0.0.1"))
    self.assertFalse(target.allows("127.0.0.2"))
    self.assertTrue(target.claim("127.0.0.1"))
    self.assertFalse(target.claim("127.0.0.1"))
    target.release()

    self.assertEqual(
      volume.request_for("mute-set", "true"),
      {"action": "mute", "value": True},
    )
    with self.assertRaises(ValueError):
      volume.request_for("mute-set", "toggle")

  def test_volume_controller_applies_changes_off_the_request_thread(self):
    class FakeCast:
      def __init__(self):
        self.status = SimpleNamespace(volume_level=0.31, volume_muted=True)
        self.updated = threading.Event()
        self.volume = None
        self.muted = None

      def set_volume(self, value, timeout=3):
        self.volume = value

      def set_volume_muted(self, muted, timeout=3):
        self.muted = muted
        self.updated.set()

    with tempfile.TemporaryDirectory() as temporary:
      cast = FakeCast()
      state = stream.StreamState()
      controller = stream.VolumeController(
        cast,
        state,
        Path(temporary) / "volume.json",
        "speaker-id",
      )
      response = controller.apply({"action": "mute", "value": False})
      self.assertFalse(response["muted"])
      worker = threading.Thread(target=controller.run)
      worker.start()
      self.assertTrue(cast.updated.wait(1))
      state.stopping.set()
      controller.changed.set()
      worker.join(timeout=1)
      self.assertFalse(worker.is_alive())


if __name__ == "__main__":
  unittest.main()
