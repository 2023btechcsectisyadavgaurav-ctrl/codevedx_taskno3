#!/usr/bin/env python3
"""Small web app instrumented for Cloud Monitoring.

Public endpoints:   /          status page
                    /healthz   health check used by the uptime checks
Protected endpoints (need the demo token, used to generate load and trigger alerts):
                    /slow?ms=800            respond slowly (latency alert)
                    /error                  return HTTP 500 (error-rate alert)
                    /cpu?seconds=120        burn CPU on every core (CPU alert)
                    /mem?mb=1400&seconds=120 hold memory (memory alert; capped at 1500 MB)

Every request is written as one JSON line to /var/log/demo-app/app.log, which the Ops Agent
ships to Cloud Logging; log-based metrics turn it into request, error and latency metrics.
"""
import hmac
import json
import os
import socket
import subprocess
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

TOKEN = os.environ.get("DEMO_TOKEN", "")
LOG_PATH = os.environ.get("LOG_PATH", "/var/log/demo-app/app.log")
PORT = int(os.environ.get("PORT", "80"))
INSTANCE = socket.gethostname()
CPUS = os.cpu_count() or 1

os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
LOG = open(LOG_PATH, "a", buffering=1)


def clamp(value, low, high):
    return max(low, min(high, value))


def int_param(query, key, default):
    try:
        return int(query.get(key, [default])[0])
    except (TypeError, ValueError):
        return default


class Handler(BaseHTTPRequestHandler):
    server_version = "demo-app"

    def log_message(self, *args):  # silence the default stderr access log
        pass

    def reply(self, status, body, content_type="text/plain; charset=utf-8"):
        data = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        return status

    def authorized(self, query):
        supplied = query.get("token", [""])[0] or self.headers.get("X-Demo-Token", "")
        return bool(TOKEN) and hmac.compare_digest(supplied, TOKEN)

    def do_GET(self):
        started = time.time()
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        path = parsed.path
        status = 500
        try:
            status = self.route(path, query)
        except Exception as exc:  # report it as a 500 so it shows up in the error metric
            status = self.reply(500, "internal error: %s\n" % exc)
        finally:
            record = {
                "time": datetime.now(timezone.utc).isoformat(),
                "instance": INSTANCE,
                "method": "GET",
                "path": path,  # the query string is never logged (it may contain the token)
                "status": status,
                "latency_ms": round((time.time() - started) * 1000, 1),
            }
            LOG.write(json.dumps(record) + "\n")

    def route(self, path, query):
        if path == "/healthz":
            return self.reply(200, "ok\n")

        if path == "/":
            page = (
                "<!doctype html><html><head><meta charset='utf-8'><title>Monitored app</title></head>"
                "<body style='font-family:system-ui;max-width:640px;margin:4rem auto'>"
                "<h1>Cloud Monitoring demo app</h1>"
                "<p>Instance: <code>%s</code></p>"
                "<p>Every request is logged and turned into request, error and latency metrics.</p>"
                "</body></html>" % INSTANCE
            )
            return self.reply(200, page, "text/html; charset=utf-8")

        if path in ("/slow", "/error", "/cpu", "/mem"):
            if not self.authorized(query):
                return self.reply(403, "forbidden\n")

            if path == "/slow":
                ms = clamp(int_param(query, "ms", 800), 0, 5000)
                time.sleep(ms / 1000.0)
                return self.reply(200, "slept %d ms\n" % ms)

            if path == "/error":
                return self.reply(500, "simulated server error\n")

            if path == "/cpu":
                seconds = clamp(int_param(query, "seconds", 120), 1, 600)
                workers = clamp(int_param(query, "workers", CPUS), 1, 4)
                for _ in range(workers):
                    subprocess.Popen(
                        ["timeout", str(seconds), "python3", "-c", "while True: pass"],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
                return self.reply(200, "burning %d core(s) for %d s\n" % (workers, seconds))

            if path == "/mem":
                mb = clamp(int_param(query, "mb", 600), 1, 1500)
                seconds = clamp(int_param(query, "seconds", 120), 1, 600)
                code = "x = b'a' * (%d * 1024 * 1024); import time; time.sleep(%d)" % (mb, seconds)
                subprocess.Popen(
                    ["timeout", str(seconds + 5), "python3", "-c", code],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                return self.reply(200, "holding %d MB for %d s\n" % (mb, seconds))

        return self.reply(404, "not found\n")


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
