import '../connection.dart';
import '../trace.dart';

/// MCP tool: track_repaints
///
/// Toggle repaint tracking. When enabled, Flutter shows which render objects
/// are repainting. Combine with screenshot to identify excessive repaints.
Future<Map<String, Object?>> trackRepaintsTool(
  FlutterConnection connection,
  bool enable,
  TraceLog trace,
) async {
  final startTime = trace.start();

  try {
    await connection.service.callServiceExtension(
      'ext.flutter.inspector.trackRepaintWidgets',
      isolateId: connection.isolateId,
      args: {'enabled': enable.toString()},
    );

    trace.complete(
      action: 'track_repaints',
      startTimeMs: startTime,
      target: enable.toString(),
      result: 'success',
    );

    return {
      'status': 'success',
      'tracking': enable,
      'message': enable
          ? 'Repaint tracking enabled. Repainting regions are highlighted.'
          : 'Repaint tracking disabled.',
    };
  } catch (e) {
    trace.complete(
      action: 'track_repaints',
      startTimeMs: startTime,
      result: 'error',
      error: e.toString(),
    );
    return {'status': 'error', 'error': e.toString()};
  }
}
