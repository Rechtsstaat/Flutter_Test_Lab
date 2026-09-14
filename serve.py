#!/usr/bin/env python3
"""재현본 정적 서버 — 캐시 비활성.

    python3 재현/serve.py 8779    →  http://localhost:8779/직방/직방_매물등록폼_재현.html
"""
import functools, http.server, os, socketserver, sys

ROOT = os.path.dirname(os.path.abspath(__file__))

class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        super().end_headers()
    def log_message(self, *a): pass

port = int(sys.argv[1]) if len(sys.argv) > 1 else 8779
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("127.0.0.1", port), functools.partial(H, directory=ROOT)) as httpd:
    print("serving %s on http://localhost:%d" % (ROOT, port))
    httpd.serve_forever()
