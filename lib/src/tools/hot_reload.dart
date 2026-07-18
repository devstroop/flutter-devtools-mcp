import 'package:logging/logging.dart';

import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';

final _log = Logger('HotReload');

/// MCP tool: hot_reload
///
/// Trigger a hot reload on the connected Flutter app.
Future<Map<String, Object?>> hotReloadImpl(
  FlutterConnection connection,
) async {
  try {
    final report = await connection.hotReload();
    // Refresh cached isolate and root library — hot reload can change them
    await connection.refreshIsolate();
    _log.info('Hot reload succeeded (success: ${report.success})');
    return {
      'status': 'success',
      'success': report.success,
    };
  } catch (e) {
    _log.warning('Hot reload failed: $e');
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
      return hotReloadImpl(conn);
    },
  );
}
