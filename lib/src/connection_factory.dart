import 'dart:async';
import 'package:logging/logging.dart';

import 'connection.dart';
import 'discovery.dart';

final _log = Logger('ConnectionFactory');

/// Manages the lifecycle of [FlutterConnection] instances.
///
/// Caches WebSocket connections by VM Service URL so repeated tool calls
/// to the same Flutter app reuse an existing connection.
/// Auto-discovers Flutter apps via mDNS when no URL is provided.
///
/// Usage:
/// ```dart
/// final factory = ConnectionFactory();
///
/// // Auto-discover
/// final conn = await factory.getConnection();
///
/// // Or target a specific app
/// final conn = await factory.getConnection('ws://127.0.0.1:54321/ws');
///
/// // Cleanup
/// await factory.disconnectAll();
/// ```
class ConnectionFactory {
  final Map<String, FlutterConnection> _cache = {};
  final List<FlutterConnection> _pendingConnects = [];

  /// Get or create a cached connection for [url].
  ///
  /// If [url] is null, auto-discovers a Flutter app via mDNS and uses
  /// the first one found. Throws [StateError] if no Flutter app is
  /// running in debug mode.
  ///
  /// Subsequent calls with the same URL return the cached connection
  /// without reconnecting.
  Future<FlutterConnection> getConnection([String? url]) async {
    // Auto-discover if no URL provided
    url ??= await _discoverFirst();
    if (url == null) {
      throw StateError(
        'No Flutter debug app found. Start one with "flutter run --debug" '
        'and try again, or pass an explicit vmServiceUrl.',
      );
    }

    // Return cached connection if it exists and is still connected
    if (_cache.containsKey(url)) {
      return _cache[url]!;
    }

    // Create and connect a new connection
    final conn = FlutterConnection(vmServiceUrl: url);
    await conn.connect();
    _cache[url] = conn;
    _log.info('Connected to Flutter app at $url');

    return conn;
  }

  /// Close all cached WebSocket connections.
  Future<void> disconnectAll() async {
    _log.info('Disconnecting ${_cache.length} cached connection(s)...');
    for (final entry in _cache.entries) {
      try {
        await entry.value.disconnect();
      } catch (e) {
        _log.warning('Error disconnecting ${entry.key}: $e');
      }
    }
    _cache.clear();
  }

  /// Discover the first running Flutter debug app via mDNS.
  ///
  /// Returns the WebSocket URL of the first discovered app, or null if
  /// no app was found within the mDNS scan timeout.
  Future<String?> _discoverFirst() async {
    _log.info('No vmServiceUrl provided — scanning for Flutter apps via mDNS...');
    final services = await discoverFlutterVmServices();

    if (services.isEmpty) {
      _log.warning('No running Flutter debug apps found via mDNS.');
      return null;
    }

    if (services.length > 1) {
      _log.info('Multiple Flutter apps found — using the first:');
      for (final s in services) {
        _log.info('  ${s.wsUrl}');
      }
    }

    final url = services.first.wsUrl;
    _log.info('Auto-discovered: $url');
    return url;
  }
}
