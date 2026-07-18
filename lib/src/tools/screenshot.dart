import 'package:logging/logging.dart';

import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';

final _log = Logger('Screenshot');

/// MCP tool: screenshot
///
/// Capture the current screen as base64-encoded PNG.
Future<Map<String, Object?>> screenshotImpl(
  FlutterConnection connection,
) async {
  try {
    final response = await connection.screenshot();
    final bytes = response.json?['screenshot'] as String?;
    _log.info('Screenshot captured (${bytes?.length ?? 0} bytes)');
    return {
      'status': 'success',
      'format': 'png',
      'encoding': 'base64',
      if (bytes != null) 'data': bytes,
    };
  } catch (e) {
    _log.warning('Screenshot failed: $e');
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createScreenshotTool() {
  return ToolDef(
    name: 'screenshot',
    description: 'Capture the current screen as base64-encoded PNG.',
    inputSchema: {
      'type': 'object',
      'properties': {},
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      final result = await screenshotImpl(conn);
      if (result['status'] == 'success') {
        result['_mcp_content_type'] = 'image';
      }
      return result;
    },
  );
}
