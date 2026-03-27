import '../connection.dart';
import '../trace.dart';

/// MCP tool: hot_reload
///
/// Trigger a hot reload on the connected Flutter app.
Future<Map<String, Object?>> hotReloadTool(
  FlutterConnection connection,
  TraceLog trace,
) async {
  final startTime = trace.start();

  try {
    final report = await connection.hotReload();

    trace.complete(
      action: 'hot_reload',
      startTimeMs: startTime,
      result: 'success',
    );

    return {
      'status': 'success',
      'success': report.success,
    };
  } catch (e) {
    trace.complete(
      action: 'hot_reload',
      startTimeMs: startTime,
      result: 'error',
      error: e.toString(),
    );
    rethrow;
  }
}
