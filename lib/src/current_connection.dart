import 'dart:async';
import 'connection.dart';
import 'registry.dart';

/// Holds the single active [FlutterConnection] for this MCP server.
///
/// After calling the [connect] tool, the connection is stored here.
/// All other tools read from this singleton via [get()].
///
/// Automatically detects stale connections and transparently reconnects
/// using the last known VM Service URL.
class CurrentConnection {
  static FlutterConnection? _conn;
  static String? _vmServiceUrl;

  /// Whether a connection is currently active.
  static bool get isConnected => _conn != null;

  /// Get the current connection, verifying it is still alive.
  ///
  /// If the underlying WebSocket has been closed by the VM Service,
  /// this method attempts a transparent reconnection using the last
  /// known URL. Throws [StateError] if not connected and reconnection
  /// fails or no URL was saved.
  static Future<FlutterConnection> get() async {
    final c = _conn;
    if (c == null) {
      throw StateError(
        'Not connected to any Flutter app. '
        'Use the connect tool first with a VM Service URL:\n'
        '  connect(vmServiceUrl: "http://127.0.0.1:PORT/TOKEN=/")\n'
        'The URL appears in your flutter run output.',
      );
    }

    // Fast path: check if still alive with a quick ping
    if (await _isAlive(c)) return c;

    // Connection is stale — try transparent reconnection
    final url = _vmServiceUrl;
    if (url == null) {
      _conn = null;
      throw StateError(
        'Connection to the Flutter app was lost and no VM Service URL '
        'is available for reconnection. Use connect again.',
      );
    }

    try {
      await c.disconnect();
    } catch (_) {}
    _conn = null;

    final fresh = FlutterConnection(vmServiceUrl: url);
    await fresh.connect();
    _conn = fresh;
    return fresh;
  }

  /// Set (or replace) the active connection, closing any previous one.
  /// Call [Registry.register] *after* this on success so a failed set()
  /// doesn't leave a stale active entry in the registry.
  static Future<void> set(FlutterConnection connection) async {
    await disconnect();
    _vmServiceUrl = connection.vmServiceUrl;
    _conn = connection;
  }

  /// Disconnect and clear the active connection.
  /// Marks the URL as inactive in the registry (kept for history).
  static Future<void> disconnect() async {
    final c = _conn;
    final url = _vmServiceUrl;

    // Clear state first — subsequent operations see no connection.
    _conn = null;
    _vmServiceUrl = null;

    // Update registry before the actual disconnect so a failed disconnect
    // doesn't leave the URL falsely marked as active.
    if (url != null) {
      try {
        Registry.instance.markDisconnected(url);
      } catch (_) {
        // Registry persistence is non-critical — don't break disconnect.
      }
    }

    if (c != null) {
      await c.disconnect();
    }
  }

  /// Quick health check — ping the VM Service and verify the cached isolate.
  ///
  /// After a hot reload failure, the WebSocket stays alive but the isolate
  /// is gone. We must check both to detect a stale connection.
  ///
  /// We deliberately do NOT check isolate.runnable — the isolate is briefly
  /// paused during hot reload, and checking runnable would cause false
  /// negatives during that transient window, interrupting the workflow.
  static Future<bool> _isAlive(FlutterConnection conn) async {
    try {
      await conn.service.getVM();
      // Deep check: verify the cached isolate still exists.
      // isolateId throws StateError if _mainIsolate is null — guard here.
      String id;
      try {
        id = conn.isolateId;
      } on StateError {
        return false;
      }
      if (id.isEmpty) return false;
      await conn.service.getIsolate(id); // throws if isolate is gone
      return true;
    } catch (_) {
      return false;
    }
  }
}
