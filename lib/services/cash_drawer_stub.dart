/// Stub implementation for web — TCP sockets are not available.
///
/// The cash drawer cannot be opened directly from a web browser; users
/// should deploy the app as a native desktop or mobile application for
/// full cash-drawer support.
Future<bool> openCashDrawerNetwork(String host, int port) async => false;
