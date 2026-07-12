import '../connection.dart';
import '../trace.dart';
import '../connection_factory.dart';
import '../mcp_transport.dart';

/// MCP tool: toggle_repaint_rainbow
///
/// Toggle repaint rainbow — applies a rotating color overlay to repainted
/// regions. Useful for identifying widgets that repaint too frequently.
/// Take a screenshot after enabling to see repaint activity.
Future<Map<String, Object?>> toggleRepaintRainbowImpl(
  FlutterConnection connection,
  bool enable,
  TraceLog trace,
) async {
  final startTime = trace.start();

  try {
    final response = await connection.service.callServiceExtension(
      'ext.flutter.repaintRainbow',
      isolateId: connection.isolateId,
      args: {'enabled': enable.toString()},
    );

    final current = response.json?['enabled'] as String?;

    trace.complete(
      action: 'toggle_repaint_rainbow',
      startTimeMs: startTime,
      target: enable.toString(),
      result: 'success',
    );

    return {
      'status': 'success',
      'repaintRainbow': (current ?? enable.toString()) == 'true',
      'message': enable
          ? 'Repaint rainbow enabled. Regions change color on each repaint.'
          : 'Repaint rainbow disabled.',
    };
  } catch (e) {
    trace.complete(
      action: 'toggle_repaint_rainbow',
      startTimeMs: startTime,
      result: 'error',
      error: e.toString(),
    );
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createToggleRepaintRainbowTool(ConnectionFactory factory) {
  return ToolDef(
    name: 'toggle_repaint_rainbow',
    description:
        'Toggle repaint rainbow — applies a rotating color overlay to repainted regions for identifying widgets that repaint too frequently.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'enable': {
          'type': 'boolean',
          'description': 'true to show repaint rainbow, false to hide'
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
      return toggleRepaintRainbowImpl(conn, args['enable'] as bool, TraceLog());
    },
  );
}
