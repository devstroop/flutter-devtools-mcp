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

  FlutterConnection({required this.vmServiceUrl}) {
    if (!_isLocalhost(vmServiceUrl)) {
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
    if (id == null) throw StateError('No root library found. Call connect() first.');
    return id;
  }

  /// Connect to the VM Service and discover the main Flutter isolate.
  Future<void> connect() async {
    _log.info('Connecting to $vmServiceUrl');
    _service = await vmServiceConnectUri(vmServiceUrl);
    final vm = await _service!.getVM();
    _mainIsolate = vm.isolates?.firstWhere(
      (iso) => iso.name == 'main',
      orElse: () => vm.isolates!.first,
    );
    _log.info('Connected. Isolate: ${_mainIsolate?.id}');

    // Discover the root library for evaluate() calls
    final isolate = await _service!.getIsolate(isolateId);
    final rootLib = isolate.rootLib;
    if (rootLib != null) {
      _rootLibraryId = rootLib.id;
      _log.fine('Root library: ${rootLib.uri} (${rootLib.id})');
    } else {
      // Fallback: find a Flutter library from the loaded libraries
      final libs = isolate.libraries ?? [];
      for (final lib in libs) {
        final uri = lib.uri ?? '';
        if (uri.startsWith('package:flutter/')) {
          _rootLibraryId = lib.id;
          _log.fine('Using Flutter library: $uri (${lib.id})');
          break;
        }
      }
      _rootLibraryId ??= libs.isNotEmpty ? libs.first.id : null;
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

  /// Call a Flutter driver extension method.
  ///
  /// Returns the unwrapped result map from the service extension response.
  Future<Map<String, Object?>> callDriver(
    String method,
    Map<String, Object?> args,
  ) async {
    final response = await service.callServiceExtension(
      'ext.flutter.driver.$method',
      isolateId: isolateId,
      args: args,
    );
    final json = response.json!;
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

  /// Evaluate a Dart expression in the main isolate's root library scope.
  Future<InstanceRef> evaluate(String expression) async {
    final result = await service.evaluate(isolateId, rootLibraryId, expression);
    return result as InstanceRef;
  }

  /// Disconnect from the VM Service.
  Future<void> disconnect() async {
    await _service?.dispose();
    _service = null;
    _mainIsolate = null;
    _log.info('Disconnected');
  }

  static bool _isLocalhost(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.host == '127.0.0.1' || uri.host == 'localhost';
  }
}
