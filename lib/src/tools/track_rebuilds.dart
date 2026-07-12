import '../connection.dart';
import '../trace.dart';
import '../connection_factory.dart';
import '../mcp_transport.dart';

/// MCP tool: track_rebuilds
///
/// Toggle tracking of widget rebuilds. When enabled, Flutter annotates
/// widgets with rebuild counts. Use the screenshot tool to capture the
/// visual overlay, or snapshot to see if the tree has changed.
Future<Map<String, Object?>> trackRebuildsImpl(
  FlutterConnection connection,
  bool enable,
  TraceLog trace,
) async {
  final startTime = trace.start();

  try {
    await connection.service.callServiceExtension(
      'ext.flutter.inspector.trackRebuildDirtyWidgets',
      isolateId: connection.isolateId,
      args: {'enabled': enable.toString()},
    );

    trace.complete(
      action: 'track_rebuilds',
      startTimeMs: startTime,
      target: enable.toString(),
      result: 'success',
    );

    return {
      'status': 'success',
      'tracking': enable,
      'message': enable
          ? 'Rebuild tracking enabled. Widgets show rebuild counts in the inspector overlay.'
          : 'Rebuild tracking disabled.',
    };
  } catch (e) {
    trace.complete(
      action: 'track_rebuilds',
      startTimeMs: startTime,
      result: 'error',
      error: e.toString(),
    );
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createTrackRebuildsTool(ConnectionFactory factory) {
  return ToolDef(
    name: 'track_rebuilds',
    description:
        'Toggle tracking of widget rebuilds. When enabled, Flutter annotates widgets with rebuild counts.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'enable': {
          'type': 'boolean',
          'description': 'true to enable rebuild tracking, false to disable'
        },
        'vmServiceUrl': {
          'type': 'string',
          'description':
              'VM Service WebSocket URL (optional — auto-discovers via mDNS if omitted)'
        },
      },
      'required': ['enable'],
    },
    handler: (args) async {
      final conn = await factory.getConnection(args['vmServiceUrl'] as String?);
      return trackRebuildsImpl(conn, args['enable'] as bool, TraceLog());
    },
  );
}
