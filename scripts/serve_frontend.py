#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Threaded static server for the built Flutter web app, with NO-CACHE headers.

Why this exists:
    Browsers apply heuristic caching when no Cache-Control is sent, and may keep
    serving a stale `main.dart.js` / font files for a very long time. Because
    Flutter emits a fixed `main.dart.js` filename (no content hash), a stale copy
    is never invalidated on rebuild -- which is exactly how users end up seeing
    old bugs (e.g. tofu icon fonts / missing icons) after we already fixed and
    rebuilt them.

Threading matters (critical):
    Flutter web loads DOZENS of assets in parallel (main.dart.js, canvaskit.js,
    canvaskit.wasm, fonts, images...). A single-threaded http server serializes
    them; one slow / keep-alive / stuck connection blocks the whole queue and
    later requests time out -- producing flaky "missing icon / broken favicon /
    blank page". This server therefore uses a *threaded* server (one handler
    thread per connection) so slow clients can never stall the rest.

Every response is sent with:
    Cache-Control: no-store, no-cache, must-revalidate, max-age=0
    Pragma: no-cache
    Expires: 0

Usage:
    python serve_frontend.py [port] [root]
Defaults: port=8080, root=<repo>/frontend/build/web
"""
import http.server
import socketserver
import sys
import os
import mimetypes
import http.client
from urllib.parse import urlparse

# Make sure the MIME types Flutter/CanvasKit need are known, independent of the
# host's system mimetypes database (which is often incomplete / wrong on Windows).
_EXTRA_TYPES = {
    ".js": "text/javascript",
    ".mjs": "text/javascript",
    ".json": "application/json",
    ".wasm": "application/wasm",
    ".otf": "font/otf",
    ".ttf": "font/ttf",
    ".woff": "font/woff",
    ".woff2": "font/woff2",
    ".ico": "image/x-icon",
    ".png": "image/png",
    ".svg": "image/svg+xml",
    ".webp": "image/webp",
    ".css": "text/css",
    ".html": "text/html; charset=utf-8",
    ".map": "application/json",
}
for _ext, _type in _EXTRA_TYPES.items():
    mimetypes.add_type(_type, _ext)

NO_CACHE = {
    "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
    "Pragma": "no-cache",
    "Expires": "0",
}


def _is_local_origin(origin: str) -> bool:
    """是否为本机来源（localhost / 127.0.0.1 / ::1，任意端口）。"""
    if not origin:
        return False
    try:
        p = urlparse(origin)
    except ValueError:
        return False
    return p.scheme in ("http", "https") and p.hostname in ("localhost", "127.0.0.1", "::1")


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    # Use HTTP/1.1 so keep-alive works and large files stream properly.
    protocol_version = "HTTP/1.1"

    # 同源反向代理 /api/tts/* → 后端 8190。
    # 这样前端朗读音频与页面同源（http://localhost:8080/api/tts/speak）：
    #   - 彻底避开跨端口 / CORS / 自动播放来源限制；
    #   - 前端只需相对 URL，任何 host 打开页面都能用。
    BACKEND_HOST = "127.0.0.1"
    BACKEND_PORT = int(os.environ.get("TTS_BACKEND_PORT", "8190"))

    def _proxy_tts(self):
        parsed = urlparse(self.path)
        if not parsed.path.startswith("/api/tts"):
            return False
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None
        try:
            conn = http.client.HTTPConnection(self.BACKEND_HOST, self.BACKEND_PORT, timeout=30)
            fwd = {k: v for k, v in self.headers.items()
                   if k.lower() not in ("host", "connection")}
            conn.request(self.command, self.path, body=body, headers=fwd)
            resp = conn.getresponse()
            data = resp.read()
            self.send_response(resp.status)
            for k, v in resp.getheaders():
                if k.lower() in ("transfer-encoding", "connection", "content-length"):
                    continue
                self.send_header(k, v)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            conn.close()
        except Exception as e:  # 后端未启动等 → 让前端回退浏览器语音
            self.send_response(502)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(str(e))))
            self.end_headers()
            self.wfile.write(str(e).encode())
        return True

    def do_GET(self):
        if self._proxy_tts():
            return
        super().do_GET()

    def do_POST(self):
        if self._proxy_tts():
            return
        self.send_error(404)

    def do_OPTIONS(self):
        if urlparse(self.path).path.startswith("/api/tts"):
            self.send_response(200)
            # 同源反代：页面与 /api/tts 同源，浏览器不会触发跨域预检，
            # 这里仅作健壮性兜底。只回显本机来源，避免使用 "*" 通配
            # （既不必要，也会被 CORS 静态扫描判为过度放开）。
            origin = self.headers.get("Origin", "")
            allowed = origin if _is_local_origin(origin) else "http://localhost:8080"
            self.send_header("Access-Control-Allow-Origin", allowed)
            self.send_header("Vary", "Origin")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        self.send_error(404)

    def end_headers(self):
        for k, v in NO_CACHE.items():
            self.send_header(k, v)
        super().end_headers()

    def guess_type(self, path):
        # Prefer our explicit table for the extensions we care about.
        ext = os.path.splitext(path)[1].lower()
        if ext in _EXTRA_TYPES:
            return _EXTRA_TYPES[ext]
        return super().guess_type(path)

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


class ThreadingTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    daemon_threads = True          # don't let handler threads block shutdown
    allow_reuse_address = True     # quick restart on Windows (avoid TIME_WAIT)
    request_queue_size = 128       # bigger accept backlog so bursts don't get refused


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    if len(sys.argv) > 2:
        root = sys.argv[2]
    else:
        here = os.path.dirname(os.path.abspath(__file__))
        root = os.path.join(here, "..", "frontend", "build", "web")
    root = os.path.abspath(root)
    if not os.path.exists(os.path.join(root, "index.html")):
        sys.stderr.write("[serve_frontend] WARNING: index.html not found in %s\n" % root)

    os.chdir(root)
    with ThreadingTCPServer(("0.0.0.0", port), NoCacheHandler) as httpd:
        sys.stderr.write(
            "[serve_frontend] serving %s on http://0.0.0.0:%d (threaded, no-cache)\n"
            % (root, port)
        )
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
