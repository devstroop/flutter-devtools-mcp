import 'package:logging/logging.dart';

import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';

final _log = Logger('TrackRepaints');

/// MCP tool: track_repaints
///
/// Toggle repaint tracking.
Future<Map<String, Object?>> trackRepaintsImpl(
  FlutterConnection connection,
  bool enable,
) async {
  try {
    await connection.service.callServiceExtension(
      'ext.flutter.inspector.trackRepaintWidgets',
      isolateId: connection.isolateId,
      args: {'enabled': enable.toString()},
    );

    _log.info('Repaint tracking: $enable');
    return {
      'status': 'success',
      'tracking': enable,
      'message': enable
          ? 'Repaint tracking enabled. Repainting regions are highlighted.'
          : 'Repaint tracking disabled.',
    };
  } catch (e) {
    _log.warning('Track repaints failed: $e');
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createTrackRepaintsTool() {
  return ToolDef(
    name: 'track_repaints',
    description:
        'Toggle repaint tracking. When enabled, Flutter shows which render objects are repainting.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'enable': {
          'type': 'boolean',
          'description': 'true to enable repaint tracking, false to disable'
        },
      },
      'required': ['enable'],
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      return trackRepaintsImpl(conn, args['enable'] as bool);
    },
  );
}
