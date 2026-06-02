#!/usr/bin/env python3
import json
import os
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

SERVICE_NAME = os.getenv("SERVICE_NAME", "orders-api")
SECRET_PATH = os.getenv("SECRET_PATH", "/mnt/secrets-store/message")
STARTED_AT = time.time()
REQUESTS = 0


def secret_value():
    try:
        with open(SECRET_PATH, "r", encoding="utf-8") as secret_file:
            return secret_file.read().strip()
    except FileNotFoundError:
        return "secret-not-mounted"


def payload(path):
    return {
        "service": SERVICE_NAME,
        "path": path,
        "version": os.getenv("APP_VERSION", "0.1.0"),
        "uptime_seconds": round(time.time() - STARTED_AT, 2),
        "secret_message": secret_value(),
        "orders": [{"id": "ord-1001", "status": "accepted"}],
    }


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        global REQUESTS
        REQUESTS += 1

        if self.path in ("/healthz", "/readyz"):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok\n")
            return

        if self.path == "/metrics":
            body = (
                "# HELP idp_requests_total Total HTTP requests handled by this service.\n"
                "# TYPE idp_requests_total counter\n"
                f'idp_requests_total{{service="{SERVICE_NAME}"}} {REQUESTS}\n'
            )
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.end_headers()
            self.wfile.write(body.encode("utf-8"))
            return

        body = json.dumps(payload(self.path), indent=2).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        print(f"{SERVICE_NAME} {self.address_string()} {fmt % args}", flush=True)


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8080"))
    HTTPServer(("", port), Handler).serve_forever()

