import '../connection.dart';
import '../connection_factory.dart';
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

ToolDef createHotReloadTool(ConnectionFactory factory) {
  return ToolDef(
    name: 'hot_reload',
    description: 'Trigger a hot reload on the connected Flutter app.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'vmServiceUrl': {
          'type': 'string',
          'description': 'VM Service WebSocket URL (optional — auto-discovers via mDNS if omitted)',
        },
      },
    },
    handler: (args) async {
      final conn = await factory.getConnection(args['vmServiceUrl'] as String?);
      return hotReloadImpl(conn, TraceLog());
    },
  );
}
