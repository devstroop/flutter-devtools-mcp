import 'dart:convert';
import '../connection_factory.dart';
import '../discovery.dart';
import '../mcp_transport.dart';

/// MCP tool impl: discover
///
/// Scan for running Flutter debug apps via mDNS.
Future<Map<String, Object?>> discoverImpl() async {
  final services = await discoverFlutterVmServices();
  final apps = services.map((s) => s.wsUrl).toList();
  if (apps.isEmpty) {
    return {
      'status': 'ok',
      'apps': apps,
      'message':
          'No running Flutter debug apps found. Start one with: flutter run --debug',
    };
  }
  return {
    'status': 'ok',
    'apps': apps,
    'message':
        'Found ${apps.length} running Flutter app(s). Pass one to connect, or omit vmServiceUrl to auto-connect.',
  };
}

ToolDef createDiscoverTool(ConnectionFactory factory) {
  return ToolDef(
    name: 'discover',
    description:
        'ATTACH to a running Flutter app by passing its VM Service URL to connect. '
        'This tool scans for running Flutter debug apps via mDNS and returns their URLs.',
    inputSchema: {
      'type': 'object',
      'properties': {},
    },
    handler: (args) async {
      final result = await discoverImpl();
      return {
        'content': [
          {'type': 'text', 'text': json.encode(result)},
        ],
      };
    },
  );
}
