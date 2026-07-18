import 'package:logging/logging.dart';

import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';

final _log = Logger('GetErrors');

/// MCP tool: get_errors
///
/// Retrieve Flutter framework errors (structured errors) from the running app.
/// First ensures structured error collection is enabled (idempotent), then
/// calls `ext.flutter.inspector.getErrorInfo` which returns all errors
/// collected since the last reload.
Future<Map<String, Object?>> getErrorsImpl(
  FlutterConnection connection,
) async {
  try {
    // Ensure structured errors are enabled so getErrorInfo returns data.
    // Idempotent — safe to call multiple times.
    try {
      await connection.service.callServiceExtension(
        'ext.flutter.inspector.structuredErrors',
        isolateId: connection.isolateId,
        args: {'enabled': 'true'},
      );
    } catch (_) {
      // May already be enabled or not supported on older Flutter.
    }

    final response = await connection.service.callServiceExtension(
      'ext.flutter.inspector.getErrorInfo',
      isolateId: connection.isolateId,
      args: {},
    );

    final data = response.json;
    final errors = (data?['errors'] as List<dynamic>?) ?? [];

    // Restore top-level errorsSinceReload as the max of per-item values
    // for backward compatibility with consumers expecting the old format.
    int maxErrorsSinceReload = 0;
    final mapped = errors.map((e) {
      final m = e as Map<String, dynamic>;
      final perItem = m['errorsSinceReload'] as int? ?? 0;
      if (perItem > maxErrorsSinceReload) maxErrorsSinceReload = perItem;
      return {
        'description': m['description'] ?? m['renderedErrorText'],
        'type': m['type'],
        'errorsSinceReload': perItem,
      };
    }).toList();

    // Reset the error counter so subsequent calls don't return duplicates.
    // Best-effort — a failure here should not break the tool.
    try {
      await connection.evaluate('FlutterError.resetErrorCount()');
    } catch (_) {}

    return {
      'status': 'success',
      'errorCount': errors.length,
      'errorsSinceReload': maxErrorsSinceReload,
      'errors': mapped,
      if (errors.isEmpty) 'message': 'No Flutter framework errors detected.',
    };
  } catch (e) {
    final errStr = e.toString();
    // Release-mode Flutter apps don't support this extension.
    if (errStr.contains('-32601') || errStr.contains('Unknown method')) {
      return {
        'status': 'error',
        'error': 'Errors not available in this build mode. '
            'Run the Flutter app in debug mode to capture framework errors.',
      };
    }
    _log.fine('get_errors failed: $e');
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createGetErrorsTool() {
  return ToolDef(
    name: 'get_errors',
    description: 'Retrieve Flutter framework errors from the running app.',
    inputSchema: {
      'type': 'object',
      'properties': {},
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      return getErrorsImpl(conn);
    },
  );
}
