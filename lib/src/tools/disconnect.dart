import '../current_connection.dart';
import '../mcp_transport.dart';

/// MCP tool: disconnect
///
/// Disconnect from the currently connected Flutter app.
ToolDef createDisconnectTool() {
  return ToolDef(
    name: 'disconnect',
    description:
        'Disconnect from the currently connected Flutter app. '
        'Closes the VM Service WebSocket connection.',
    inputSchema: {
      'type': 'object',
      'properties': {},
    },
    handler: (args) async {
      await CurrentConnection.disconnect();
      return {
        'content': [
          {'type': 'text', 'text': '{"status":"disconnected"}'},
        ],
      };
    },
  );
}
