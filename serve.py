#!/usr/bin/env python3
"""
Custom HTTP Server for Godot 4 Web Exports
Ensures proper MIME types and Cross-Origin isolation headers (COOP & COEP)
which are required by modern web browsers for WebAssembly and SharedArrayBuffer.
"""

import http.server
import socketserver
import sys
import os

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080

class GodotWebHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # Security headers required for Godot WebAssembly multithreading & audio
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        super().end_headers()

    def guess_type(self, path):
        if path.endswith(".wasm"):
            return "application/wasm"
        elif path.endswith(".pck"):
            return "application/octet-stream"
        elif path.endswith(".js"):
            return "application/javascript"
        elif path.endswith(".json"):
            return "application/json"
        elif path.endswith(".svg"):
            return "image/svg+xml"
        return super().guess_type(path)

if __name__ == "__main__":
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), GodotWebHandler) as httpd:
        print("=======================================================")
        print(f"🚀 Plants vs Zombies Web Dev Server running at:")
        print(f"👉 http://localhost:{PORT}/web_preview/ (Interactive Web Preview)")
        print(f"👉 http://localhost:{PORT}/web_export/  (Godot Web Export)")
        print("=======================================================")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down server...")

