import 'dart:convert';
import '../current_connection.dart';
import '../mcp_transport.dart';

/// MCP tool: status
///
/// Check whether we're currently connected to a Flutter app.
Future<Map<String, Object?>> statusImpl() async {
  return {
    'connected': CurrentConnection.isConnected,
  };
}

ToolDef createStatusTool() {
  return ToolDef(
    name: 'status',
    description: 'Check whether the tool is currently connected to a Flutter debug app. '
        'Returns {"connected": true/false}.',
    inputSchema: {
      'type': 'object',
      'properties': {},
    },
    handler: (args) async {
      final result = await statusImpl();
      return {
        'content': [
          {'type': 'text', 'text': json.encode(result)},
        ],
      };
    },
  );
}
