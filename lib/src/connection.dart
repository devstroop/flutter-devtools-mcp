import 'dart:async';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'package:logging/logging.dart';

final _log = Logger('Connection');

/// Manages the WebSocket connection to a Flutter app's VM Service.
///
/// Connects to the observatory URL printed by `flutter run`, discovers
/// the main Flutter isolate, and provides access to the [VmService] client
/// for calling inspector and driver extensions.
class FlutterConnection {
  final String vmServiceUrl;
  VmService? _service;
  IsolateRef? _mainIsolate;
  String? _rootLibraryId;

  /// Completer that resolves when [disconnect] is called while [connect] is
  /// in-flight. The in-progress [connect] checks this between each step and
  /// throws [CancelledException] if cancellation was requested.
  Completer<void>? _cancelCompleter;

  FlutterConnection({required String vmServiceUrl})
      : vmServiceUrl = _normalizeVmUrl(vmServiceUrl) {
    if (!_isLocalhost(this.vmServiceUrl)) {
      throw ArgumentError('Only localhost VM Service URLs are allowed');
    }
  }

  VmService get service {
    final s = _service;
    if (s == null) throw StateError('Not connected. Call connect() first.');
    return s;
  }

  String get isolateId {
    final iso = _mainIsolate;
    if (iso == null) throw StateError('No Flutter isolate found.');
    return iso.id!;
  }

  /// The root library ID of the main isolate, used as the target for evaluate().
  String get rootLibraryId {
    final id = _rootLibraryId;
    if (id == null) {
      throw StateError('No root library found. Call connect() first.');
    }
    return id;
  }

  /// Cancel a connection in progress. If [connect] is running, it will
  /// abort at the next cancellation point. This is a no-op if the
  /// connection is already established or already cancelled.
  void cancel() {
    if (_cancelCompleter == null) {
      // cancel() called before connect() started — eagerly create a
      // completed completer so connect() sees the cancellation.
      _cancelCompleter = Completer<void>()..complete();
      return;
    }
    if (!_cancelCompleter!.isCompleted) {
      _cancelCompleter!.complete();
    }
  }

  /// Throw [StateError] if cancellation was requested.
  void _checkCancelled() {
    if (_cancelCompleter != null && _cancelCompleter!.isCompleted) {
      throw StateError('Connection cancelled');
    }
  }

  /// Connect to the VM Service and discover the main Flutter isolate.
  /// Can be aborted by calling [cancel] from another thread.
  /// When cancelled, the underlying WebSocket is closed immediately.
  Future<void> connect() async {
    // If cancellation was already requested before connect() started
    // (e.g. timer fired before we reached this method), bail out immediately.
    if (_cancelCompleter != null && _cancelCompleter!.isCompleted) {
      throw StateError('Connection cancelled');
    }
    _cancelCompleter = Completer<void>();
    // Mask the auth token in log output.
    _log.info('Connecting to ${maskUrlToken(vmServiceUrl)}');

    // Race: cancel signal vs WebSocket handshake.
    final connectFuture = vmServiceConnectUri(vmServiceUrl);
    final winner = await Future.any([
      connectFuture.then((s) => 0), // connect finished
      _cancelCompleter!.future.then((_) => 1), // cancelled
    ]);
    if (winner == 1) {
      // Don't await connectFuture — it may never complete (e.g. network
      // partition). Schedule disposal as fire-and-forget instead.
      unawaited(
        connectFuture.then((svc) => svc.dispose()).catchError((_) {}),
      );
      throw StateError('Connection cancelled');
    }
    _service = await connectFuture;
    _checkCancelled();

    final vm = await _service!.getVM();
    _checkCancelled();

    // Find the main Flutter isolate
    final isolates = vm.isolates;
    if (isolates == null || isolates.isEmpty) {
      throw StateError(
        'Connected to VM Service but no isolates found. '
        'Ensure a Flutter app is running in debug mode.',
      );
    }
    final hadMain = isolates.any((iso) => iso.name == 'main');
    if (!hadMain) {
      _log.warning(
        'No isolate named "main" found — using first of ${isolates.length} '
        'isolates: ${isolates.first.id}. '
        'If this seems wrong, check that the Flutter app is in debug mode.',
      );
    }
    _mainIsolate = isolates.firstWhere(
      (iso) => iso.name == 'main',
      orElse: () => isolates.first,
    );
    _checkCancelled();
    _log.info('Connected. Isolate: ${_mainIsolate?.id}');

    // Discover the root library for evaluate() calls
    final isolate = await _service!.getIsolate(isolateId);
    _checkCancelled();
    final rootLib = isolate.rootLib;
    if (rootLib != null) {
      _rootLibraryId = rootLib.id;
      _log.fine('Root library: ${rootLib.uri} (${rootLib.id})');
    } else {
      // Fallback: find a suitable library for evaluate() scope.
      // Prefer the first non-Flutter package: URI (app code), then
      // package:flutter/ itself, then the first available library.
      final libs = isolate.libraries ?? [];
      String? packageUri;
      for (final lib in libs) {
        final uri = lib.uri ?? '';
        if (uri.startsWith('package:flutter/')) {
          _rootLibraryId ??= lib.id;
        } else if (uri.startsWith('package:') && packageUri == null) {
          packageUri = lib.id;
        }
      }
      if (packageUri != null) {
        _rootLibraryId = packageUri;
        _log.fine('Using package library for evaluate(): $packageUri');
      } else if (libs.isNotEmpty && _rootLibraryId == null) {
        _rootLibraryId = libs.first.id;
      }
    }
  }

  /// Call a Flutter inspector extension method.
  ///
  /// Returns the unwrapped result map from the service extension response.
  /// (`callServiceExtension` wraps the actual data inside a `result` key.)
  Future<Map<String, Object?>> callInspector(
    String method,
    Map<String, Object?> args,
  ) async {
    final response = await service.callServiceExtension(
      'ext.flutter.inspector.$method',
      isolateId: isolateId,
      args: args,
    );
    final json = response.json!;
    // Service extension responses wrap the payload under 'result'.
    if (json.containsKey('result') && json['result'] is Map) {
      return Map<String, Object?>.from(json['result'] as Map);
    }
    return json;
  }

  /// Take a screenshot via the Flutter screenshot extension.
  Future<Response> screenshot() {
    return service.callServiceExtension(
      '_flutter.screenshot',
      isolateId: isolateId,
    );
  }

  /// Trigger hot reload.
  Future<ReloadReport> hotReload() {
    return service.reloadSources(isolateId);
  }

  /// Re-discover the main isolate and root library after a hot reload/restart.
  ///
  /// Hot reload can change loaded libraries (new `package:` imports), making
  /// the cached `_rootLibraryId` stale. Call this after every reload or
  /// reassemble to keep `evaluate()` working.
  ///
  /// Unlike `connect()`, this does NOT assume the isolate ID has changed —
  /// hot reload and reassemble keep the same isolate ID. This method refreshes
  /// `_rootLibraryId` and verifies the isolate is still alive.
  Future<void> refreshIsolate() async {
    _log.fine('Refreshing isolate state...');
    try {
      final vm = await _service!.getVM();
      final isolates = vm.isolates;
      IsolateRef? newIsolate;
      if (isolates != null && isolates.isNotEmpty) {
        if (!isolates.any((iso) => iso.name == 'main')) {
          _log.warning(
            'No isolate named "main" during refresh — using first of '
            '${isolates.length} isolates: ${isolates.first.id}.',
          );
        }
        newIsolate = isolates.firstWhere(
          (iso) => iso.name == 'main',
          orElse: () => isolates.first,
        );
      }
      if (newIsolate == null) {
        _log.warning('No isolates found during refresh — isolate may be dead');
        return;
      }

      final newId = newIsolate.id;
      if (newId == null) {
        _log.warning('New isolate has no id — cannot refresh');
        return;
      }

      // Resolve new root library first, then swap atomically.
      // This ensures _mainIsolate and _rootLibraryId are always in sync.
      String? newRootId;
      final isolate = await _service!.getIsolate(newId);
      final rootLib = isolate.rootLib;
      if (rootLib != null) {
        newRootId = rootLib.id;
        _log.fine('Resolved root library: ${rootLib.uri} (${rootLib.id})');
      } else {
        // Fallback: find a suitable library to use as evaluation scope.
        // Prefer the first package: URI (likely app code), then any
        // package:flutter/ library as a last resort. This mirrors the
        // same fallback used in connect().
        final libs = isolate.libraries ?? [];
        String? packageUri;
        for (final lib in libs) {
          final uri = lib.uri ?? '';
          if (uri.startsWith('package:flutter/')) {
            // Remember Flutter framework as fallback
            newRootId ??= lib.id;
          } else if (uri.startsWith('package:') && packageUri == null) {
            // Prefer first app/library package: URI
            packageUri = lib.id;
          }
        }
        if (packageUri != null) {
          newRootId = packageUri;
          _log.fine('Resolved package library for evaluate(): $packageUri');
        } else if (newRootId != null) {
          _log.fine('Resolved Flutter framework library: $newRootId');
        } else {
          // No usable library found — invalidate cached root library.
          // Keeping a stale ID from a different isolate would cause cryptic
          // failures in evaluate(); nulling it produces a clear error.
          _log.warning(
            'Could not find a suitable root library after refresh. '
            'Invalidating _rootLibraryId (was $_rootLibraryId). '
            'Scanned ${libs.length} libraries, none matched package:flutter/.',
          );
          newRootId = null;
        }
      }

      // Atomic swap: both fields updated together after all async work succeeds.
      // newRootId is null when rootLib.id was null or when no suitable fallback
      // was found — in that case we explicitly invalidate _rootLibraryId so
      // evaluate() gives a clear error rather than using a stale reference.
      _mainIsolate = newIsolate;
      _rootLibraryId = newRootId;
      _log.info(
          'Refresh complete. Isolate: $newId, rootLibrary: $_rootLibraryId');
    } catch (e) {
      _log.warning('Failed to refresh isolate state: $e');
      // Do NOT rethrow — a failed refresh should not crash the caller.
      // The stale connection will be detected by _isAlive() on next use.
    }
  }

  /// Evaluate a Dart expression in the main isolate's root library scope.
  ///
  /// Throws [StateError] if the expression evaluation fails at runtime.
  Future<InstanceRef> evaluate(String expression) async {
    final result = await service.evaluate(isolateId, rootLibraryId, expression);
    if (result is ErrorRef) {
      throw StateError(
          'Evaluate failed: ${result.message ?? result.kind ?? 'unknown error'}');
    }
    return result as InstanceRef;
  }

  /// Disconnect from the VM Service.
  Future<void> disconnect() async {
    await _service?.dispose();
    _service = null;
    _mainIsolate = null;
    _log.info('Disconnected');
  }

  /// Normalize a VM Service URL to WebSocket format.
  ///
  /// Accepts both `http://` and `ws://` schemes, with or without `/ws` path.
  /// Flutter's `flutter run` prints an http:// URL — this converts it
  /// to the WebSocket endpoint the VM Service expects.
  static String _normalizeVmUrl(String url) {
    var uri = Uri.tryParse(url);
    if (uri == null) return url;

    final scheme = uri.scheme;
    if (scheme == 'http') uri = uri.replace(scheme: 'ws');
    if (scheme == 'https') uri = uri.replace(scheme: 'wss');

    var path = uri.path;
    if (!path.endsWith('/ws')) {
      if (path.endsWith('/')) path = path.substring(0, path.length - 1);
      uri = uri.replace(path: '$path/ws');
    }

    return uri.toString();
  }

  /// Mask the auth token in a VM Service URL for safe logging.
  /// The token is the first path segment after the host:port.
  /// Uses Uri parsing for robust handling of all URL formats — unlike a
  /// regex, this always produces a masked result unless the URL is
  /// completely unparseable (in which case it's returned as-is).
  static String maskUrlToken(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final segments = uri.pathSegments;
    if (segments.isEmpty) return url;
    final masked = <String>['***', ...segments.skip(1)];
    return uri.replace(pathSegments: masked).toString();
  }

  static bool _isLocalhost(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host;
    return host == '127.0.0.1' || host == 'localhost' || host == '::1';
  }
}
