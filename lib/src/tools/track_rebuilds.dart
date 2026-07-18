import 'package:logging/logging.dart';

import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';

final _log = Logger('TrackRebuilds');

/// MCP tool: track_rebuilds
///
/// Toggle tracking of widget rebuilds.
Future<Map<String, Object?>> trackRebuildsImpl(
  FlutterConnection connection,
  bool enable,
) async {
  try {
    await connection.service.callServiceExtension(
      'ext.flutter.inspector.trackRebuildDirtyWidgets',
      isolateId: connection.isolateId,
      args: {'enabled': enable.toString()},
    );

    _log.info('Rebuild tracking: $enable');
    return {
      'status': 'success',
      'tracking': enable,
      'message': enable
          ? 'Rebuild tracking enabled. Widgets show rebuild counts in the inspector overlay.'
          : 'Rebuild tracking disabled.',
    };
  } catch (e) {
    _log.warning('Track rebuilds failed: $e');
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createTrackRebuildsTool() {
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
      },
      'required': ['enable'],
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      return trackRebuildsImpl(conn, args['enable'] as bool);
    },
  );
}
