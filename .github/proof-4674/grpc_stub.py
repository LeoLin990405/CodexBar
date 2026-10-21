#!/usr/bin/env python3
"""Fork-only proof stub for steipete/CodexBar#4679.

Serves a local TLS endpoint for `grok.com` that answers the grok.com billing
gRPC-web request with the #3261 implicit-zero protobuf payload for an ACTIVE
weekly billing period (start = now - 3 days, end = now + 4 days), and answers
`cli-chat-proxy.grok.com/v1/settings` with a synthetic plan tier.

No real network or credentials are involved; the faked hosts are mapped to
127.0.0.1 by the proof workflow and the synthetic bearer token is validated by
nothing but the local stub.
"""

import json
import os
import ssl
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

TLS_DIR = os.environ.get("PROOF_TLS_DIR", "/tmp/proof-tls")


def varint(value: int) -> bytes:
    out = bytearray()
    while value >= 0x80:
        out.append((value & 0x7F) | 0x80)
        value >>= 7
    out.append(value)
    return bytes(out)


def implicit_zero_frame() -> bytes:
    """Same protobuf shape as GrokZeroUsageTests.payload(periodType: 2)."""
    now = int(time.time())
    start = now - 3 * 86400
    end = now + 4 * 86400
    start_ts = b"\x08" + varint(start)
    end_ts = b"\x08" + varint(end)
    period = (
        b"\x08\x02"
        + b"\x12" + bytes([len(start_ts)]) + start_ts
        + b"\x1A" + bytes([len(end_ts)]) + end_ts
    )
    config = b"\x42" + bytes([len(period)]) + period
    payload = b"\x0A" + bytes([len(config)]) + config
    return b"\x00" + len(payload).to_bytes(4, "big") + payload


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):  # noqa: N802 - stdlib API
        sys.stderr.write("proof-stub: " + fmt % args + "\n")

    def do_GET(self):  # noqa: N802 - stdlib API
        if self.path.startswith("/v1/settings"):
            body = json.dumps({"subscription_tier_display": "SuperGrok Heavy"}).encode()
        else:
            body = b"{}"
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):  # noqa: N802 - stdlib API
        length = int(self.headers.get("Content-Length") or 0)
        request_body = self.rfile.read(length) if length else b""
        sys.stderr.write(f"proof-stub: POST {self.path} ({len(request_body)} request bytes)\n")
        body = implicit_zero_frame()
        self.send_response(200)
        self.send_header("Content-Type", "application/grpc-web+proto")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 443
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(
        os.path.join(TLS_DIR, "server.pem"),
        os.path.join(TLS_DIR, "server.key"))
    server = HTTPServer(("0.0.0.0", port), Handler)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    sys.stderr.write(f"proof-stub: listening on 0.0.0.0:{port}\n")
    sys.stderr.flush()
    server.serve_forever()


if __name__ == "__main__":
    main()
