#!/usr/bin/env python3
"""
cash_drawer_bridge.py
=====================
Local HTTP bridge for Goldfish POS.

When the POS (running as a web app in the browser) wants to open the cash
drawer, it sends a POST request to http://localhost:<PORT>/open-drawer.
This script receives that request and forwards the ESC/POS kick command to
the USB receipt printer via the Windows print spooler.

Requirements
------------
  pip install pywin32

Usage
-----
  python cash_drawer_bridge.py

Keep this window open whenever the POS is in use.
To start automatically at Windows login, put a shortcut to this script in
the Startup folder:  Win+R  ->  shell:startup
"""

import sys
import json
from http.server import HTTPServer, BaseHTTPRequestHandler

# ── Configuration ──────────────────────────────────────────────────────────
PORT = 8765           # Must match "Bridge Port" in POS > Admin > Cash Drawer

PRINTER_NAME = ""     # Leave blank to use the Windows default printer.
                      # Or set to the exact name shown in
                      # Control Panel > Devices and Printers, e.g.:
                      #   PRINTER_NAME = "EPSON TM-T20III"

# ESC/POS command: kick cash drawer connected to drawer port 0 (~50 ms pulse)
KICK_COMMAND = bytes([0x1B, 0x70, 0x00, 0x19, 0xFA])
# ───────────────────────────────────────────────────────────────────────────


def open_drawer():
    """Send the ESC/POS kick command to the printer via the Windows spooler."""
    try:
        import win32print

        printer = PRINTER_NAME or win32print.GetDefaultPrinter()
        handle = win32print.OpenPrinter(printer)
        try:
            win32print.StartDocPrinter(handle, 1, ("Cash Drawer", None, "RAW"))
            try:
                win32print.StartPagePrinter(handle)
                win32print.WritePrinter(handle, KICK_COMMAND)
                win32print.EndPagePrinter(handle)
            finally:
                win32print.EndDocPrinter(handle)
        finally:
            win32print.ClosePrinter(handle)

        return True, "ok"
    except Exception as exc:
        return False, str(exc)


class _Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):          # suppress default access log
        pass

    def _send_cors(self):
        """Allow requests from any origin (browser / localhost POS app)."""
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def do_OPTIONS(self):                       # CORS preflight
        self.send_response(204)
        self._send_cors()
        self.end_headers()

    def do_POST(self):
        if self.path == "/open-drawer":
            ok, msg = open_drawer()
            body = json.dumps({"ok": ok, "message": msg}).encode()
            self.send_response(200 if ok else 500)
            self._send_cors()
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            status = "opened" if ok else f"ERROR: {msg}"
            print(f"  Cash drawer {status}")
        else:
            self.send_response(404)
            self.end_headers()


if __name__ == "__main__":
    server = HTTPServer(("localhost", PORT), _Handler)
    print(f"Goldfish POS cash drawer bridge")
    print(f"Listening on http://localhost:{PORT}/")
    print("Press Ctrl+C to stop.\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
        sys.exit(0)
