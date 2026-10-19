#!/usr/bin/env python3
"""Encode bounded helper stdin as the existing JSON-string payload envelope.

An over-limit sample is omitted in full: partial socket/process counters must
not become a rate baseline. Drain the pipe so pipefail still detects producer
failures rather than a deliberate early close causing SIGPIPE.
"""
from __future__ import annotations

import json
import sys

MAX_ENVELOPE_BYTES = 1024 * 1024


def encode(data: dict) -> str:
    return json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n"


def envelope(stream, metadata: dict) -> str:
    raw = stream.read(MAX_ENVELOPE_BYTES + 1)
    oversized = len(raw) > MAX_ENVELOPE_BYTES
    while stream.read(65536):
        pass
    data = dict(metadata, ok=True, payload="" if oversized else raw.decode("utf-8", "replace"))
    result = encode(data)
    if oversized or len(result.encode("utf-8")) > MAX_ENVELOPE_BYTES:
        data.update(payload="", truncated=True, payloadLimitBytes=MAX_ENVELOPE_BYTES)
        result = encode(data)
    return result


def main(args: list[str]) -> None:
    kind, timestamp, *fields = args
    metadata = {"ts": float(timestamp)}
    if kind == "procs":
        metadata["metric"] = "procs"
    elif kind == "net":
        name, rx, tx, addresses = fields
        metadata.update(ifname=name, ifRx=int(rx), ifTx=int(tx), addrs=addresses.splitlines())
    else:
        raise ValueError("unknown helper envelope")
    sys.stdout.buffer.write(envelope(sys.stdin.buffer, metadata).encode("utf-8"))


if __name__ == "__main__":
    main(sys.argv[1:])
