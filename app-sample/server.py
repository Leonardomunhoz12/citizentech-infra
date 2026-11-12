#!/usr/bin/env python3
"""Aplicação de exemplo CitizenTech (HTTP simples, sem dependências).

Serve a página inicial e o endpoint /health. Substitua por sua aplicação real
definindo APP_REPO_URL e APP_START_CMD em config/citizentech.env.
"""
import json
import os
import socket
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = os.environ.get("HOST", "127.0.0.1")
PORT = int(os.environ.get("PORT", "8080"))
START = time.time()


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="text/html; charset=utf-8"):
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            payload = {"status": "ok", "host": socket.gethostname(),
                       "uptime_s": int(time.time() - START)}
            self._send(200, json.dumps(payload), "application/json")
        elif self.path in ("/", "/index.html"):
            with open(os.path.join(os.path.dirname(__file__), "index.html"), encoding="utf-8") as f:
                self._send(200, f.read())
        else:
            self._send(404, "Não encontrado", "text/plain; charset=utf-8")

    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt % args), flush=True)


if __name__ == "__main__":
    print(f"CitizenTech ouvindo em {HOST}:{PORT}", flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
