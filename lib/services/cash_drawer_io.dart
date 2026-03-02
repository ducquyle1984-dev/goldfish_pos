import 'dart:io';

/// Opens a cash drawer connected to an ESC/POS receipt printer via TCP.
///
/// Most cash drawers plug into the printer's DK/RJ-12 port and the printer
/// exposes itself on the local network. The standard TCP port is 9100.
///
/// The ESC/POS command sequence used:
///   `ESC p 0 t1 t2` → kick cash drawer port 0
///   - ESC (0x1B) p (0x70) pin=0 (0x00) t1=25ms (0x19) t2=250ms (0xFA)
Future<bool> openCashDrawerNetwork(String host, int port) async {
  try {
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 5),
    );
    // ESC/POS kick cash drawer command (port 0, pulse ~50ms)
    socket.add(const [0x1B, 0x70, 0x00, 0x19, 0xFA]);
    await socket.flush();
    await socket.close();
    return true;
  } catch (_) {
    return false;
  }
}
