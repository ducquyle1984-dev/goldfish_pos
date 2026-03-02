#!/usr/bin/env python3
"""
cash_drawer_bridge.py  —  Goldfish POS Cash Drawer Bridge
==========================================================
Local HTTP server that receives open-drawer requests from the POS web app
and sends an ESC/POS kick command to the USB receipt printer via Windows.

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
import os
import logging
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
# ── Logging setup: writes to bridge.log next to this script ───────────────
_script_dir = os.path.dirname(os.path.abspath(__file__))
_log_path   = os.path.join(_script_dir, 'bridge.log')
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s  %(levelname)-7s  %(message)s',
    handlers=[
        logging.FileHandler(_log_path, encoding='utf-8'),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger('bridge')
# ───────────────────────────────────────────────────────────────────────

def open_drawer():
    """Send the ESC/POS kick command to the printer via the Windows spooler."""
    try:
        import win32print  # type: ignore[import]  # pywin32 — Windows only, installed by installer

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
        log.error('open_drawer failed: %s', exc)
        return False, str(exc)


class _Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        log.info(fmt, *args)

    def _cors(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        if self.path == '/status':
            body = json.dumps({
                'ok': True,
                'service': 'Goldfish POS Cash Drawer Bridge',
                'port': PORT,
                'log': _log_path,
            }).encode()
            self.send_response(200)
            self._cors()
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == '/open-drawer':
            ok, msg = open_drawer()
            body = json.dumps({'ok': ok, 'message': msg}).encode()
            self.send_response(200 if ok else 500)
            self._cors()
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()


if __name__ == '__main__':
    log.info('=' * 55)
    log.info('Goldfish POS Cash Drawer Bridge starting')
    log.info('Port : %d', PORT)
    log.info('Log  : %s', _log_path)
    log.info('=' * 55)

    try:
        server = HTTPServer(('localhost', PORT), _Handler)
        server.serve_forever()
    except OSError as e:
        log.critical('Cannot bind to port %d: %s', PORT, e)
        log.critical('Is another instance already running?')
        sys.exit(1)
    except KeyboardInterrupt:
        log.info('Stopped by user.')
        sys.exit(0)
    except Exception as e:
        log.critical('Unexpected error: %s', e, exc_info=True)
        sys.exit(1)
