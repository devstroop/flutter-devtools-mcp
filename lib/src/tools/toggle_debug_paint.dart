import '../connection.dart';
import '../trace.dart';
import '../connection_factory.dart';
import '../mcp_transport.dart';

/// MCP tool: toggle_debug_paint
///
/// Toggle debug paint overlays — shows widget boundaries, padding, and
/// alignment visualizations. Take a screenshot after enabling to see the
/// overlay.
Future<Map<String, Object?>> toggleDebugPaintImpl(
  FlutterConnection connection,
  bool enable,
  TraceLog trace,
) async {
  final startTime = trace.start();

  try {
    final response = await connection.service.callServiceExtension(
      'ext.flutter.debugPaint',
      isolateId: connection.isolateId,
      args: {'enabled': enable.toString()},
    );

    final current = response.json?['enabled'] as String?;

    trace.complete(
      action: 'toggle_debug_paint',
      startTimeMs: startTime,
      target: enable.toString(),
      result: 'success',
    );

    return {
      'status': 'success',
      'debugPaint': (current ?? enable.toString()) == 'true',
      'message': enable
          ? 'Debug paint enabled. Widget boundaries and padding are now visible.'
          : 'Debug paint disabled.',
    };
  } catch (e) {
    trace.complete(
      action: 'toggle_debug_paint',
      startTimeMs: startTime,
      result: 'error',
      error: e.toString(),
    );
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createToggleDebugPaintTool(ConnectionFactory factory) {
  return ToolDef(
    name: 'toggle_debug_paint',
    description:
        'Toggle debug paint overlay — shows widget boundaries, padding, and alignment guides.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'enable': {
          'type': 'boolean',
          'description': 'true to show debug paint, false to hide'
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
      return toggleDebugPaintImpl(conn, args['enable'] as bool, TraceLog());
    },
  );
}
