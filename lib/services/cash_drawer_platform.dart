/// Conditional export — uses dart:io Socket on native platforms,
/// falls back to a no-op stub on web.
export 'cash_drawer_stub.dart' if (dart.library.io) 'cash_drawer_io.dart';
