import io
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

from tests.py.helpers import SCRIPTS, load_script

transport = load_script("helper-envelope.py")


class Envelope(unittest.TestCase):
    def test_large_payload_round_trip(self):
        payload = ('"quoted" \\ <img src=x> 日本語\n' * 10000).encode()
        self.assertGreater(len(payload), 128 * 1024)
        encoded = transport.envelope(io.BytesIO(payload), {"metric": "procs", "ts": 1})
        result = json.loads(encoded)
        self.assertTrue(result["ok"])
        self.assertEqual(result["payload"], payload.decode())
        self.assertNotIn("truncated", result)

    def test_limits_raw_and_encoded_bytes_and_drains_input(self):
        limit = transport.MAX_ENVELOPE_BYTES
        # Control characters fit as input but expand during JSON escaping.
        for payload in (b"x" * (limit + 10), b"\x01" * (limit // 2)):
            with self.subTest(size=len(payload)):
                stream = io.BytesIO(payload)
                encoded = transport.envelope(stream, {"ts": 1})
                result = json.loads(encoded)
                self.assertTrue(result["truncated"])
                self.assertEqual(result["payloadLimitBytes"], limit)
                self.assertEqual(result["payload"], "")
                self.assertLessEqual(len(encoded.encode()), limit)
                self.assertEqual(stream.tell(), len(payload))


class WrapperTransport(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        for name in ("process-sample", "process-net", "helper-envelope.py"):
            shutil.copy2(Path(SCRIPTS) / name, self.root / name)
        # Substitute only executable discovery. The actual wrapper's pipeline,
        # pipefail, timeout, encoding, and failure handling run unchanged.
        network = self.root / "process-net"
        text = network.read_text().replace(
            'SS=$(resolve_bin ss) || fail "ss not found (iproute2)"',
            "SS=" + shlex.quote(str(self.root / "fake-ss")),
        )
        network.write_text(text)

    def tearDown(self):
        self.tmp.cleanup()

    def producer(self, kind, payload, status=0):
        data = self.root / "payload"
        data.write_bytes(payload)
        if kind == "procs":
            path = self.root / "qproc.py"
            source = f"import sys\nsys.stdout.buffer.write(open({str(data)!r}, 'rb').read())\nsys.exit({status})\n"
        else:
            path = self.root / "fake-ss"
            source = f"#!/usr/bin/env python3\nimport sys\nsys.stdout.buffer.write(open({str(data)!r}, 'rb').read())\nsys.exit({status})\n"
        path.write_text(source)
        path.chmod(0o700)

    def run_wrapper(self, kind):
        args = [str(self.root / ("process-sample" if kind == "procs" else "process-net"))]
        args.append("3" if kind == "procs" else "lo")
        return subprocess.run(args, capture_output=True, text=True, check=False, timeout=10,
                              env=dict(os.environ, PYTHONIOENCODING="utf-8"))

    def test_both_wrappers_transport_more_than_one_argument_limit(self):
        name = 'worker "\\ 日本語 <img src=x>'
        for kind in ("procs", "net"):
            with self.subTest(kind=kind):
                if kind == "procs":
                    payload = json.dumps({"mem": [{"pid": i, "comm": name, "value": i}
                                                  for i in range(5000)]}).encode()
                else:
                    payload = (f'0 0 127.0.0.1:1 127.0.0.1:2 users:(("{name}",pid=42,fd=3))\n'
                               '\t bytes_received:100 bytes_sent:200\n').encode() * 2500
                self.assertGreater(len(payload), 128 * 1024)
                self.producer(kind, payload)
                output = self.run_wrapper(kind)
                self.assertEqual(output.returncode, 0, output.stderr)
                result = json.loads(output.stdout)
                self.assertTrue(result["ok"])
                self.assertEqual(result["payload"], payload.decode())
                self.assertNotIn("truncated", result)

    def test_oversize_is_explicit_and_producer_failure_wins(self):
        for kind in ("procs", "net"):
            for status in (0, 1):
                with self.subTest(kind=kind, status=status):
                    self.producer(kind, b"x" * (transport.MAX_ENVELOPE_BYTES + 1), status)
                    output = self.run_wrapper(kind)
                    result = json.loads(output.stdout)
                    self.assertEqual(output.returncode, status)
                    self.assertEqual(result["ok"], status == 0)
                    if status == 0:
                        self.assertTrue(result["truncated"])
                        self.assertEqual(result["payload"], "")
                    else:
                        self.assertIn("failed", result["error"])
