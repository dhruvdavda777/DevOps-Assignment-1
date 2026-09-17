"""Smallest possible Hello World web app using only the standard library.

Deliberately has no third-party dependencies, so the image needs no pip install
and stays small. Dhruv Davda - 24BCS10203.
"""
from http.server import BaseHTTPRequestHandler, HTTPServer
import os
import socket

PORT = int(os.environ.get("PORT", "8000"))

PAGE = """<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Hello World - Python</title></head>
<body style="font-family: system-ui, sans-serif; text-align:center; padding-top:80px;">
  <h1>Hello World from Python</h1>
  <p>Dhruv Davda &middot; 24BCS10203 &middot; Group A</p>
  <p>http.server running inside container {hostname}</p>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        # A container orchestrator needs a cheap endpoint to poll.
        if self.path == "/health":
            body = b'{"status":"ok"}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
        else:
            body = PAGE.format(hostname=socket.gethostname()).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        # Log to stdout so that "docker logs" shows the requests.
        print("%s - %s" % (self.address_string(), fmt % args), flush=True)


if __name__ == "__main__":
    print(f"listening on 0.0.0.0:{PORT}", flush=True)
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
