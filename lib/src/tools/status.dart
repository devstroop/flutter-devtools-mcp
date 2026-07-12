import 'dart:convert';
import '../connection_factory.dart';
import '../discovery.dart';
import '../mcp_transport.dart';

/// MCP tool impl: status
///
/// Check connection status and detect available Flutter debug apps.
Future<Map<String, Object?>> statusImpl(ConnectionFactory factory) async {
  final services = await discoverFlutterVmServices();
  final apps = services.map((s) => s.wsUrl).toList();
  return {
    'connected': factory.hasConnection,
    'appCount': apps.length,
    'apps': apps,
  };
}

ToolDef createStatusTool(ConnectionFactory factory) {
  return ToolDef(
    name: 'status',
    description: 'Check connection status. Returns whether connected, '
        'and how many running apps are detectable via mDNS. '
        'Always call this first after connect to verify.',
    inputSchema: {
      'type': 'object',
      'properties': {},
    },
    handler: (args) async {
      final result = await statusImpl(factory);
      return {
        'content': [
          {'type': 'text', 'text': json.encode(result)},
        ],
      };
    },
  );
}
