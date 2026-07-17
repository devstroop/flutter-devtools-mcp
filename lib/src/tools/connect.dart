import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';

/// MCP tool impl: connect
///
/// Connect to a running Flutter debug app via its VM Service URL.
/// The URL is printed by `flutter run` — copy the entire http:// URL
/// including the token (e.g. http://127.0.0.1:54321/abc123=/).
ToolDef createConnectTool() {
  return ToolDef(
    name: 'connect',
    description: 'Connect to a running Flutter debug app via its VM Service URL. '
        'When you run flutter run and see '
        '"A Dart VM Service is available at: http://127.0.0.1:PORT/TOKEN=/" '
        'in the terminal, copy that EXACT http:// URL (with the token) '
        'and pass it as vmServiceUrl. '
        'Auto-normalizes http:// to ws:// and appends /ws.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'vmServiceUrl': {
          'type': 'string',
          'description': 'The full VM Service URL from flutter run output, '
              'e.g. http://127.0.0.1:54321/abc123=/. '
              'Both http:// and ws:// formats work.',
        },
      },
      'required': ['vmServiceUrl'],
    },
    handler: (args) async {
      final url = (args['vmServiceUrl'] as String?)?.trim();
      if (url == null || url.isEmpty) {
        return {
          'isError': true,
          'content': [
            {
              'type': 'text',
              'text': 'Error: vmServiceUrl is required.\n\n'
                  'Run your Flutter app with:\n'
                  '  flutter run --debug\n\n'
                  'Then paste the URL from the output:\n'
                  '  connect(vmServiceUrl: "http://127.0.0.1:54321/abc123=/")\n'
                  '                👆 copy the whole http:// URL here',
            },
          ],
        };
      }

      try {
        final conn = FlutterConnection(vmServiceUrl: url);
        await conn.connect();
        await CurrentConnection.set(conn);
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
              'text': '$e',
            },
          ],
        };
      }
    },
  );
}
