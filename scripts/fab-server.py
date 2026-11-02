#!/usr/bin/env python3
"""
StreamFab web server
noVNC static files + websockify proxy + small VPN API on one port,
so Traefik needs only a single router.

API (token = VNC password, header X-Fab-Token):
  GET  /api/vpn/status
  GET  /api/vpn/countries
  POST /api/vpn/up/<country>
  POST /api/vpn/next
  POST /api/vpn/off
"""

import json
import os
import subprocess

from websockify.websocketproxy import WebSocketProxy, ProxyRequestHandler

TOKEN = os.environ.get("VNC_PASSWORD", "")
VPNCTL = os.environ.get("VPNCTL", "/usr/local/bin/vpnctl")
PORT = int(os.environ.get("NOVNC_PORT", "6080"))
VNC_PORT = int(os.environ.get("VNC_PORT", "5900"))
WEB_ROOT = os.environ.get("WEB_ROOT", "/opt/novnc")


class FabHandler(ProxyRequestHandler):

    def _route(self):
        return self.path.split("?", 1)[0]

    def do_GET(self):
        if self._route().startswith("/api/"):
            return self.handle_api()
        return super().do_GET()

    def do_POST(self):
        if self._route().startswith("/api/"):
            return self.handle_api()
        self.send_error(405)

    def handle_api(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            self.rfile.read(length)

        if TOKEN and self.headers.get("X-Fab-Token", "") != TOKEN:
            return self.reply(401, {"ok": False, "error": "Nicht autorisiert"})

        route, method = self._route(), self.command
        if method == "GET" and route == "/api/vpn/status":
            args = ["status"]
        elif method == "GET" and route == "/api/vpn/countries":
            args = ["countries"]
        elif method == "POST" and route == "/api/vpn/next":
            args = ["next"]
        elif method == "POST" and route == "/api/vpn/off":
            args = ["off"]
        elif method == "POST" and route.startswith("/api/vpn/up/"):
            args = ["up", route.rsplit("/", 1)[1]]
        else:
            return self.reply(404, {"ok": False, "error": "Unbekannter Endpunkt"})

        try:
            proc = subprocess.run([VPNCTL, *args], capture_output=True, text=True, timeout=120)
            lines = proc.stdout.strip().splitlines()
            data = json.loads(lines[-1]) if lines else {"ok": False, "error": proc.stderr.strip() or "Keine Antwort"}
        except subprocess.TimeoutExpired:
            data = {"ok": False, "error": "Zeitüberschreitung"}
        except Exception as exc:  # noqa: BLE001
            data = {"ok": False, "error": str(exc)}

        self.reply(200 if data.get("ok") else 500, data)

    def reply(self, code, data):
        body = json.dumps(data).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    server = WebSocketProxy(
        RequestHandlerClass=FabHandler,
        listen_host="",
        listen_port=PORT,
        target_host="localhost",
        target_port=VNC_PORT,
        web=WEB_ROOT,
        file_only=True,
    )
    server.start_server()
