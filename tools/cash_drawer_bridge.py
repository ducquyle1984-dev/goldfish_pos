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
import socket
import logging
from http.server import HTTPServer, BaseHTTPRequestHandler

# ── Configuration ──────────────────────────────────────────────────────────
PREFERRED_PORT = 8765  # Preferred port; bridge auto-selects if this is taken.
                       # Must match "Bridge Port" in POS > Admin > Cash Drawer
                       # (the POS scans nearby ports automatically).

PRINTER_NAME = ""     # Leave blank to use the Windows default printer.
                      # Or set to the exact name shown in
                      # Control Panel > Devices and Printers, e.g.:
                      #   PRINTER_NAME = "EPSON TM-T20III"

# ESC/POS command: kick cash drawer connected to drawer port 0 (~50 ms pulse)
KICK_COMMAND = bytes([0x1B, 0x70, 0x00, 0x19, 0xFA])
# ───────────────────────────────────────────────────────────────────────────

def _find_free_port(preferred: int) -> int:
    """Return preferred port if free, otherwise the first free port in 8765-8779."""
    for p in [preferred] + [x for x in range(8765, 8780) if x != preferred]:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.bind(('127.0.0.1', p))
                return p
        except OSError:
            continue
    return preferred  # Will fail at HTTPServer.bind — reported clearly there.
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

PORT = _find_free_port(PREFERRED_PORT)
if PORT != PREFERRED_PORT:
    log.warning('Port %d was in use; using port %d instead.', PREFERRED_PORT, PORT)


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


def print_receipt(data: dict):
    """
    Encode and print a receipt from a list of line-command objects.

    Each element of data['lines'] may be:
      {"text": "...", "align": "center"|"left"|"right", "bold": true, "size": 1|2}
      {"separator": true}   → prints a dashed rule
      {"cut": true}         → sends the paper cut command
    """
    try:
        import win32print  # type: ignore[import]
        import win32con     # type: ignore[import]

        printer_name = data.get('printer') or PRINTER_NAME or win32print.GetDefaultPrinter()

        # ── ESC/POS byte sequences ────────────────────────────────────────
        ESC   = 0x1B
        GS    = 0x1D
        INIT  = bytes([ESC, 0x40])           # Initialize
        LEFT  = bytes([ESC, 0x61, 0x00])     # Align left
        CTR   = bytes([ESC, 0x61, 0x01])     # Align center
        RIGHT = bytes([ESC, 0x61, 0x02])     # Align right
        BON   = bytes([ESC, 0x45, 0x01])     # Bold on
        BOFF  = bytes([ESC, 0x45, 0x00])     # Bold off
        SZ1   = bytes([GS, 0x21, 0x00])      # Normal size
        SZ2   = bytes([GS, 0x21, 0x11])      # Double width + height
        LF    = b'\n'
        CUT   = bytes([GS, 0x56, 0x41, 0x00])  # Partial cut
        SEPARATOR = '-' * 42

        output = bytearray(INIT)

        for line in data.get('lines', []):
            if line.get('cut'):
                output += CUT
                continue
            if line.get('separator'):
                output += LEFT + SZ1 + BOFF
                output += SEPARATOR.encode('ascii') + LF
                continue

            # Alignment
            align = line.get('align', 'left')
            if align == 'center':
                output += CTR
            elif align == 'right':
                output += RIGHT
            else:
                output += LEFT

            # Size
            size = line.get('size', 1)
            output += SZ2 if size >= 2 else SZ1

            # Bold
            output += BON if line.get('bold') else BOFF

            # Text content
            text = line.get('text', '')
            output += text.encode('utf-8', errors='replace') + LF

        # Reset printer state after printing
        output += LEFT + SZ1 + BOFF

        handle = win32print.OpenPrinter(printer_name)
        try:
            win32print.StartDocPrinter(handle, 1, ("Receipt", None, "RAW"))
            try:
                win32print.StartPagePrinter(handle)
                win32print.WritePrinter(handle, bytes(output))
                win32print.EndPagePrinter(handle)
            finally:
                win32print.EndDocPrinter(handle)
        finally:
            win32print.ClosePrinter(handle)

        log.info('Receipt printed OK on %s', printer_name)
        return True, "ok"
    except Exception as exc:
        log.error('print_receipt failed: %s', exc)
        return False, str(exc)


def get_printers() -> list:
    """Return the names of all printers visible to Windows."""
    try:
        import win32print  # type: ignore[import]
        flags = win32print.PRINTER_ENUM_LOCAL | win32print.PRINTER_ENUM_CONNECTIONS
        printers = win32print.EnumPrinters(flags, None, 2)
        return [p['pPrinterName'] for p in printers]
    except Exception as exc:
        log.error('get_printers failed: %s', exc)
        return []


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
        elif self.path == '/printers':
            names = get_printers()
            body = json.dumps({'ok': True, 'printers': names}).encode()
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
        elif self.path == '/print':
            length = int(self.headers.get('Content-Length', 0))
            raw = self.rfile.read(length)
            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                self.send_response(400)
                self.end_headers()
                return
            ok, msg = print_receipt(data)
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
    log.info('Preferred port : %d', PREFERRED_PORT)
    log.info('Actual port    : %d', PORT)
    log.info('Log            : %s', _log_path)
    log.info('Endpoints      : /status  /printers  /open-drawer  /print')
    log.info('=' * 55)

    try:
        server = HTTPServer(('127.0.0.1', PORT), _Handler)
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
