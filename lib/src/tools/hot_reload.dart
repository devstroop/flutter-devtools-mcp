import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';
import '../trace.dart';

/// MCP tool: hot_reload
///
/// Trigger a hot reload on the connected Flutter app.
Future<Map<String, Object?>> hotReloadImpl(
  FlutterConnection connection,
  TraceLog trace,
) async {
  final startTime = trace.start();

  try {
    final report = await connection.hotReload();
    // Refresh cached isolate and root library — hot reload can change them
    await connection.refreshIsolate();

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
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createHotReloadTool() {
  return ToolDef(
    name: 'hot_reload',
    description: 'Trigger a hot reload on the connected Flutter app.',
    inputSchema: {
      'type': 'object',
      'properties': {},
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      return hotReloadImpl(conn, TraceLog());
    },
  );
}
