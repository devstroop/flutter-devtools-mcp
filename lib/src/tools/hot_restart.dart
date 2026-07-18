import 'package:logging/logging.dart';

import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';

final _log = Logger('HotRestart');

/// MCP tool: hot_restart
///
/// Trigger a full hot restart (reassemble) on the connected Flutter app.
/// Unlike hot_reload, this resets all state (like restarting the app)
/// while preserving the currently loaded code.
Future<Map<String, Object?>> hotRestartImpl(
  FlutterConnection connection,
) async {
  try {
    await connection.service.callServiceExtension(
      'ext.flutter.reassemble',
      isolateId: connection.isolateId,
    );
    // Refresh cached isolate and root library — reassemble can change them
    await connection.refreshIsolate();
    _log.info('Hot restart completed');
    return {
      'status': 'success',
      'message': 'Hot restart completed. App state has been reset.',
    };
  } catch (e) {
    _log.warning('Hot restart failed: $e');
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createHotRestartTool() {
  return ToolDef(
    name: 'hot_restart',
    description:
        'Trigger a full hot restart (reassemble) on the connected Flutter app.',
    inputSchema: {
      'type': 'object',
      'properties': {},
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      return hotRestartImpl(conn);
    },
  );
}
