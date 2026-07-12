import '../connection_factory.dart';
import '../mcp_transport.dart';

/// MCP tool impl: connect
///
/// ATTACH to a running Flutter debug app via its VM Service URL.
ToolDef createConnectTool(ConnectionFactory factory) {
  return ToolDef(
    name: 'connect',
    description: 'ATTACH to a running Flutter debug app. '
        'When you run flutter run and see '
        '"A Dart VM Service is available at: http://127.0.0.1:PORT/TOKEN=/" '
        'in the terminal, copy that EXACT http:// URL (with the token) '
        'and pass it as vmServiceUrl. '
        'Auto-normalizes http:// to ws:// and appends /ws. '
        'No args = auto-discovers first running app via mDNS.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'vmServiceUrl': {
          'type': 'string',
          'description': 'The full VM Service URL from flutter run output, '
              'e.g. http://127.0.0.1:54321/abc123=/. '
              'Both http:// and ws:// formats work. '
              'Omit to auto-discover via mDNS.',
        },
      },
    },
    handler: (args) async {
      try {
        final url = args['vmServiceUrl'] as String?;
        final conn = await factory.getConnection(url);
        return {
          'content': [
            {
              'type': 'text',
              'text': '{"status":"connected","url":"${conn.vmServiceUrl}"}',
            },
          ],
        };
      } catch (e) {
        return {
          'isError': true,
          'content': [
            {
              'type': 'text',
              'text': 'Error connecting to Flutter app: $e. '
                  'Make sure the app is running with flutter run --debug '
                  'and the VM Service URL is correct.',
            },
          ],
        };
      }
    },
  );
}
