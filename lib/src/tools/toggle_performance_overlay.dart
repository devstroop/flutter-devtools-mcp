import '../connection.dart';
import '../trace.dart';

/// MCP tool: toggle_performance_overlay
///
/// Toggle the Flutter performance overlay — shows real-time frame timing
/// graphs (UI thread and raster thread). Take a screenshot to capture the
/// overlay for analysis.
Future<Map<String, Object?>> togglePerformanceOverlayTool(
  FlutterConnection connection,
  bool enable,
  TraceLog trace,
) async {
  final startTime = trace.start();

  try {
    final response = await connection.service.callServiceExtension(
      'ext.flutter.showPerformanceOverlay',
      isolateId: connection.isolateId,
      args: {'enabled': enable.toString()},
    );

    final current = response.json?['enabled'] as String?;

    trace.complete(
      action: 'toggle_performance_overlay',
      startTimeMs: startTime,
      target: enable.toString(),
      result: 'success',
    );

    return {
      'status': 'success',
      'performanceOverlay': (current ?? enable.toString()) == 'true',
      'message': enable
          ? 'Performance overlay enabled. Take a screenshot to see frame timing graphs.'
          : 'Performance overlay disabled.',
    };
  } catch (e) {
    trace.complete(
      action: 'toggle_performance_overlay',
      startTimeMs: startTime,
      result: 'error',
      error: e.toString(),
    );
    return {'status': 'error', 'error': e.toString()};
  }
}
