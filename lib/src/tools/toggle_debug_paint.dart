import 'package:logging/logging.dart';

import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';

final _log = Logger('ToggleDebugPaint');

/// MCP tool: toggle_debug_paint
///
/// Toggle debug paint overlays — shows widget boundaries, padding, and
/// alignment visualizations.
Future<Map<String, Object?>> toggleDebugPaintImpl(
  FlutterConnection connection,
  bool enable,
) async {
  try {
    final response = await connection.service.callServiceExtension(
      'ext.flutter.debugPaint',
      isolateId: connection.isolateId,
      args: {'enabled': enable.toString()},
    );

    final current = response.json?['enabled'] as String?;
    _log.info('Debug paint: ${(current ?? enable.toString()) == 'true'}');

    return {
      'status': 'success',
      'debugPaint': (current ?? enable.toString()) == 'true',
      'message': enable
          ? 'Debug paint enabled. Widget boundaries and padding are now visible.'
          : 'Debug paint disabled.',
    };
  } catch (e) {
    _log.warning('Toggle debug paint failed: $e');
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createToggleDebugPaintTool() {
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
      },
      'required': ['enable'],
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      return toggleDebugPaintImpl(conn, args['enable'] as bool);
    },
  );
}
