#!/usr/bin/env python3
"""
wol-pi — minimal Wake-on-LAN relay for a Raspberry Pi on the tailnet.

Zero runtime dependencies beyond CPython stdlib. Listens on HTTP, accepts
POST /wake, sends WoL magic packet to the configured MAC via UDP broadcast.

Designed to be reachable only from within a Tailscale tailnet — Tailscale is
the outer security boundary. An optional shared token adds a second layer.

Config: /etc/wol-pi/config.json  (see config.example.json for schema)
"""
from __future__ import annotations

import argparse
import binascii
import json
import logging
import os
import pathlib
import re
import socket
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CONFIG_PATH = pathlib.Path(os.environ.get("WOL_CONFIG", "/etc/wol-pi/config.json"))
WEB_DIR = pathlib.Path(os.environ.get("WOL_WEB_DIR", "/opt/wol-pi/web"))
MAC_RE = re.compile(r"^([0-9a-fA-F]{2}[:\-]){5}[0-9a-fA-F]{2}$")

log = logging.getLogger("wol-pi")


def load_config() -> dict:
    if not CONFIG_PATH.is_file():
        log.error("config missing at %s — create it (see config.example.json)", CONFIG_PATH)
        sys.exit(1)
    cfg = json.loads(CONFIG_PATH.read_text())
    # validate
    targets = cfg.get("targets")
    if not isinstance(targets, dict) or not targets:
        log.error("config must contain a non-empty 'targets' object (name -> MAC)")
        sys.exit(1)
    for name, mac in targets.items():
        if not isinstance(mac, str) or not MAC_RE.match(mac):
            log.error("target %r has invalid MAC %r", name, mac)
            sys.exit(1)
    return cfg


def build_magic_packet(mac: str) -> bytes:
    hw = binascii.unhexlify(mac.replace(":", "").replace("-", ""))
    return b"\xff" * 6 + hw * 16


def send_wol(mac: str, broadcast: str = "255.255.255.255", ports: tuple[int, ...] = (7, 9)) -> None:
    packet = build_magic_packet(mac)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    try:
        for port in ports:
            sock.sendto(packet, (broadcast, port))
            log.info("sent magic packet for %s to %s:%d", mac, broadcast, port)
    finally:
        sock.close()


class Handler(BaseHTTPRequestHandler):
    server_version = "wol-pi/1.0"
    sys_version = ""
    cfg: dict = {}

    def log_message(self, fmt: str, *args) -> None:
        log.info("%s - %s", self.address_string(), fmt % args)

    def _send_json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _check_token(self) -> bool:
        expected = self.cfg.get("token")
        if not expected:
            return True
        given = (
            self.headers.get("X-WOL-Token")
            or self.headers.get("Authorization", "").removeprefix("Bearer ").strip()
        )
        return given == expected

    def _serve_static(self, name: str, content_type: str) -> None:
        path = WEB_DIR / name
        if not path.is_file():
            self.send_error(404, "not found")
            return
        data = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        if self.path in ("/", "/index.html"):
            self._serve_static("index.html", "text/html; charset=utf-8")
        elif self.path == "/style.css":
            self._serve_static("style.css", "text/css; charset=utf-8")
        elif self.path == "/health":
            self._send_json(200, {"ok": True, "targets": list(self.cfg.get("targets", {}).keys())})
        elif self.path == "/targets":
            self._send_json(200, {"targets": list(self.cfg.get("targets", {}).keys())})
        else:
            self.send_error(404, "not found")

    def do_POST(self) -> None:
        if not self._check_token():
            self._send_json(401, {"error": "unauthorized"})
            return
        if self.path.startswith("/wake"):
            # Parse optional body { "target": "name" }. Default to first target.
            length = int(self.headers.get("Content-Length", "0") or 0)
            body = self.rfile.read(length) if length else b""
            target_name = None
            if body:
                try:
                    target_name = json.loads(body).get("target")
                except json.JSONDecodeError:
                    pass
            # Also allow ?target= in query
            if not target_name and "?" in self.path:
                from urllib.parse import parse_qs, urlparse
                qs = parse_qs(urlparse(self.path).query)
                target_name = (qs.get("target") or [None])[0]

            targets = self.cfg.get("targets", {})
            if not target_name:
                target_name = next(iter(targets))

            mac = targets.get(target_name)
            if not mac:
                self._send_json(404, {"error": f"unknown target: {target_name}"})
                return

            broadcast = self.cfg.get("broadcast", "255.255.255.255")
            send_wol(mac, broadcast=broadcast)
            self._send_json(200, {"ok": True, "target": target_name, "mac": mac, "sent_at": time.time()})
        else:
            self.send_error(404, "not found")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--log-level", default="INFO")
    args = ap.parse_args()

    logging.basicConfig(
        level=args.log_level.upper(),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )

    Handler.cfg = load_config()
    log.info("loaded %d target(s): %s", len(Handler.cfg["targets"]), ", ".join(Handler.cfg["targets"]))

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    log.info("listening on http://%s:%d  (expect to reach via Tailscale)", args.host, args.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("shutting down")
        server.server_close()


if __name__ == "__main__":
    main()
