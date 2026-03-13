#!/usr/bin/env python3
"""
cash_drawer_bridge.py  —  Goldfish POS Cash Drawer Bridge
==========================================================
Uses ONLY Python standard library (ctypes + subprocess).
NO pip install / NO pywin32 needed.  Works on any Python 3.6+.

Install once:  run tools\\install_bridge_service.ps1
Log file:      %APPDATA%\\GoldfishPOS\\bridge.log
"""

import sys
import json
import os
import socket
import logging
import ctypes
import ctypes.wintypes as wt
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler

# ── Configuration ──────────────────────────────────────────────────────────
PREFERRED_PORT = 8765   # POS app scans 8765-8779 automatically if this is taken
PRINTER_NAME   = ""     # Leave blank to use the Windows default printer.
                        # Or set to the exact name, e.g. "EPSON TM-T20III"

# ESC/POS kick command — drawer port 0, ~50 ms pulse
KICK_COMMAND = bytes([0x1B, 0x70, 0x00, 0x19, 0xFA])

_CREATE_NO_WND = 0x08000000   # subprocess flag: no console window
# ───────────────────────────────────────────────────────────────────────────


def _find_free_port(preferred: int) -> int:
    for p in [preferred] + [x for x in range(8765, 8780) if x != preferred]:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.bind(('127.0.0.1', p))
                return p
        except OSError:
            pass
    return preferred


# ── Logging ────────────────────────────────────────────────────────────────
_app_dir  = os.path.join(
    os.environ.get('APPDATA', os.path.dirname(os.path.abspath(__file__))),
    'GoldfishPOS',
)
_log_path = os.path.join(_app_dir, 'bridge.log')
os.makedirs(_app_dir, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s  %(levelname)-7s  %(message)s',
    handlers=[
        logging.FileHandler(_log_path, encoding='utf-8'),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger('bridge')
# ───────────────────────────────────────────────────────────────────────────

PORT = _find_free_port(PREFERRED_PORT)
if PORT != PREFERRED_PORT:
    log.warning('Port %d was in use; using port %d instead.', PREFERRED_PORT, PORT)


# ── Windows printer access via ctypes (no pywin32 needed) ──────────────────
_winspool = ctypes.WinDLL('winspool.drv', use_last_error=True)


class _DocInfo1(ctypes.Structure):
    _fields_ = [
        ('pDocName',    wt.LPCWSTR),
        ('pOutputFile', wt.LPCWSTR),
        ('pDatatype',   wt.LPCWSTR),
    ]


def _get_default_printer() -> str:
    size = wt.DWORD(0)
    _winspool.GetDefaultPrinterW(None, ctypes.byref(size))
    if size.value == 0:
        raise RuntimeError(
            'No default printer configured. '
            'Set one in Windows Settings → Printers & scanners.'
        )
    buf = ctypes.create_unicode_buffer(size.value)
    if not _winspool.GetDefaultPrinterW(buf, ctypes.byref(size)):
        raise RuntimeError(
            f'GetDefaultPrinterW failed (error {ctypes.get_last_error()})'
        )
    return buf.value


def _send_raw(printer_name: str, data: bytes) -> None:
    """Send raw bytes to a named printer via winspool.drv."""
    handle = wt.HANDLE()
    if not _winspool.OpenPrinterW(printer_name, ctypes.byref(handle), None):
        err = ctypes.get_last_error()
        raise RuntimeError(
            f'OpenPrinter("{printer_name}") failed — Windows error {err}. '
            f'Is the printer installed and the name spelled correctly?'
        )
    try:
        doc = _DocInfo1(pDocName='GoldfishPOS', pOutputFile=None, pDatatype='RAW')
        job = _winspool.StartDocPrinterW(handle, 1, ctypes.byref(doc))
        if job == 0:
            raise RuntimeError(f'StartDocPrinter failed — error {ctypes.get_last_error()}')
        try:
            _winspool.StartPagePrinter(handle)
            buf = (ctypes.c_char * len(data))(*data)
            written = wt.DWORD(0)
            _winspool.WritePrinter(handle, buf, wt.DWORD(len(data)), ctypes.byref(written))
            _winspool.EndPagePrinter(handle)
        finally:
            _winspool.EndDocPrinter(handle)
    finally:
        _winspool.ClosePrinter(handle)


def open_drawer():
    """Send the ESC/POS kick command to the printer."""
    try:
        printer = PRINTER_NAME or _get_default_printer()
        log.info('Opening drawer — printer: %s', printer)
        _send_raw(printer, KICK_COMMAND)
        log.info('Drawer opened OK.')
        return True, 'ok'
    except Exception as exc:
        log.error('open_drawer failed: %s', exc)
        return False, str(exc)


def get_printers() -> list:
    """Return all printer names visible to Windows (via PowerShell)."""
    try:
        result = subprocess.run(
            ['powershell', '-NoProfile', '-NonInteractive', '-Command',
             'Get-Printer | Select-Object -ExpandProperty Name'],
            capture_output=True, text=True, timeout=10,
            creationflags=_CREATE_NO_WND,
        )
        return [ln.strip() for ln in result.stdout.splitlines() if ln.strip()]
    except Exception as exc:
        log.error('get_printers: %s', exc)
        return []


def print_receipt(data: dict):
    """Print a receipt from a list of ESC/POS line-command objects."""
    try:
        printer_name = data.get('printer') or PRINTER_NAME or _get_default_printer()

        ESC = 0x1B
        GS  = 0x1D
        LF  = bytes([0x0A])
        INIT  = bytes([ESC, 0x40])
        LEFT  = bytes([ESC, 0x61, 0x00])
        CTR   = bytes([ESC, 0x61, 0x01])
        RIGHT = bytes([ESC, 0x61, 0x02])
        BON   = bytes([ESC, 0x45, 0x01])
        BOFF  = bytes([ESC, 0x45, 0x00])
        SZ1   = bytes([GS,  0x21, 0x00])
        SZ2   = bytes([GS,  0x21, 0x11])
        CUT   = bytes([GS,  0x56, 0x41, 0x00])
        SEP   = ('-' * 42).encode('ascii') + LF

        output = bytearray(INIT)
        for line in data.get('lines', []):
            if line.get('cut'):
                output += CUT
                continue
            if line.get('separator'):
                output += LEFT + SZ1 + BOFF + SEP
                continue
            a = line.get('align', 'left')
            output += CTR if a == 'center' else (RIGHT if a == 'right' else LEFT)
            output += SZ2 if line.get('size', 1) >= 2 else SZ1
            output += BON if line.get('bold') else BOFF
            output += line.get('text', '').encode('utf-8', errors='replace') + LF
        output += LEFT + SZ1 + BOFF

        _send_raw(printer_name, bytes(output))
        log.info('Receipt printed OK on %s', printer_name)
        return True, 'ok'
    except Exception as exc:
        log.error('print_receipt failed: %s', exc)
        return False, str(exc)


class _Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        log.debug(fmt, *args)

    def _cors(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')

    def _json(self, code: int, body_dict: dict) -> None:
        body = json.dumps(body_dict).encode()
        self.send_response(code)
        self._cors()
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        if self.path == '/status':
            self._json(200, {
                'ok': True,
                'service': 'Goldfish POS Cash Drawer Bridge',
                'port': PORT,
                'log': _log_path,
            })
        elif self.path == '/printers':
            self._json(200, {'ok': True, 'printers': get_printers()})
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == '/open-drawer':
            ok, msg = open_drawer()
            self._json(200 if ok else 500, {'ok': ok, 'message': msg})
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
            self._json(200 if ok else 500, {'ok': ok, 'message': msg})
        else:
            self.send_response(404)
            self.end_headers()


if __name__ == '__main__':
    log.info('=' * 55)
    log.info('Goldfish POS Cash Drawer Bridge  (ctypes — no pip needed)')
    log.info('Port : %d', PORT)
    log.info('Log  : %s', _log_path)
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
