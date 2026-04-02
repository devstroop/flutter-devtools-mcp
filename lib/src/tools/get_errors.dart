import '../connection.dart';
import '../trace.dart';

/// MCP tool: get_errors
///
/// Retrieve Flutter framework errors (structured errors) from the running app.
/// Subscribes to the Extension event stream, requests structured errors,
/// then collects any error events within a brief window.
Future<Map<String, Object?>> getErrorsTool(
  FlutterConnection connection,
  TraceLog trace,
) async {
  final startTime = trace.start();
  final errors = <Map<String, Object?>>[];

  try {
    // Listen for Extension events which carry structured Flutter errors
    final subscription = connection.service.onExtensionEvent.listen((event) {
      if (event.extensionKind == 'Flutter.Error') {
        final data = event.extensionData?.data;
        if (data != null) {
          errors.add({
            'description': data['description'] ?? data['renderedErrorText'],
            'errorsSinceReload': data['errorsSinceReload'],
          });
        }
      }
    });

    // Ensure the Extension stream is being listened to
    try {
      await connection.service.streamListen('Extension');
    } catch (_) {
      // Already subscribed — that's fine
    }

    // Enable structured errors so pending errors get flushed as events
    try {
      await connection.service.callServiceExtension(
        'ext.flutter.inspector.structuredErrors',
        isolateId: connection.isolateId,
        args: {'enabled': 'true'},
      );
    } catch (_) {
      // May already be enabled
    }

    // Give a short window for error events to arrive
    await Future.delayed(const Duration(milliseconds: 300));

    await subscription.cancel();

    // Also try to get the error count via evaluate
    int? errorCount;
    try {
      final result = await connection.evaluate(
        'FlutterError.resetErrorCount()',
      );
      final count = int.tryParse(result.valueAsString ?? '');
      if (count != null) errorCount = count;
    } catch (_) {
      // Not critical
    }

    trace.complete(
      action: 'get_errors',
      startTimeMs: startTime,
      result: 'success',
    );

    return {
      'status': 'success',
      'errorCount': errors.length,
      if (errorCount != null) 'errorsSinceReload': errorCount,
      'errors': errors,
      if (errors.isEmpty) 'message': 'No Flutter framework errors detected.',
    };
  } catch (e) {
    trace.complete(
      action: 'get_errors',
      startTimeMs: startTime,
      result: 'error',
      error: e.toString(),
    );
    return {'status': 'error', 'error': e.toString()};
  }
}
