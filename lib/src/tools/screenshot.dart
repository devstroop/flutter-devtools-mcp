import '../connection.dart';
import '../connection_factory.dart';
import '../mcp_transport.dart';
import '../trace.dart';

/// MCP tool: screenshot
///
/// Capture the current screen as base64-encoded PNG.
Future<Map<String, Object?>> screenshotImpl(
  FlutterConnection connection,
  TraceLog trace,
) async {
  final startTime = trace.start();

  try {
    final response = await connection.screenshot();
    final bytes = response.json?['screenshot'] as String?;

    trace.complete(
      action: 'screenshot',
      startTimeMs: startTime,
      result: 'success',
    );

    return {
      'status': 'success',
      'format': 'png',
      'encoding': 'base64',
      if (bytes != null) 'data': bytes,
    };
  } catch (e) {
    trace.complete(
      action: 'screenshot',
      startTimeMs: startTime,
      result: 'error',
      error: e.toString(),
    );
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createScreenshotTool(ConnectionFactory factory) {
  return ToolDef(
    name: 'screenshot',
    description: 'Capture the current screen as base64-encoded PNG.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'vmServiceUrl': {
          'type': 'string',
          'description': 'VM Service WebSocket URL (optional — auto-discovers via mDNS if omitted)',
        },
      },
    },
    handler: (args) async {
      final conn = await factory.getConnection(args['vmServiceUrl'] as String?);
      final result = await screenshotImpl(conn, TraceLog());
      if (result['status'] == 'success') {
        result['_mcp_content_type'] = 'image';
      }
      return result;
    },
  );
}
