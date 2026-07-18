import 'package:logging/logging.dart';

import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';

final _log = Logger('ToggleRainbow');

/// MCP tool: toggle_repaint_rainbow
///
/// Toggle repaint rainbow — rotating color overlay on repainted regions.
Future<Map<String, Object?>> toggleRepaintRainbowImpl(
  FlutterConnection connection,
  bool enable,
) async {
  try {
    final response = await connection.service.callServiceExtension(
      'ext.flutter.repaintRainbow',
      isolateId: connection.isolateId,
      args: {'enabled': enable.toString()},
    );

    final current = response.json?['enabled'] as String?;
    _log.info('Repaint rainbow: ${(current ?? enable.toString()) == 'true'}');

    return {
      'status': 'success',
      'repaintRainbow': (current ?? enable.toString()) == 'true',
      'message': enable
          ? 'Repaint rainbow enabled. Regions change color on each repaint.'
          : 'Repaint rainbow disabled.',
    };
  } catch (e) {
    _log.warning('Toggle repaint rainbow failed: $e');
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createToggleRepaintRainbowTool() {
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
      },
      'required': ['enable'],
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      return toggleRepaintRainbowImpl(conn, args['enable'] as bool);
    },
  );
}
