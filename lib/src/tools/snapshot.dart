import '../connection.dart';
import '../connection_factory.dart';
import '../mcp_transport.dart';
import '../transform.dart';

/// Raw implementation — kept public for testing.
Future<Map<String, Object?>> snapshotImpl(FlutterConnection connection) async {
  final rawTree = await connection.callInspector(
    'getRootWidgetSummaryTree',
    {'objectGroup': 'mcp-snapshot'},
  );
  return transformTree(rawTree);
}

/// MCP tool: widget_tree
///
/// Returns the current widget tree as LLM-friendly JSON.
/// Use this to see every widget on screen — its type, label, key, bounds, and children.
/// (Previously called "snapshot" — search for that term if you don't see this tool.)
ToolDef createSnapshotTool(ConnectionFactory factory) {
  return ToolDef(
    name: 'widget_tree',
    description:
        'Get the current widget tree as structured JSON — every widget, its type, label, key, bounds, and children. '
        'Use this to understand what is on screen. '
        'Also known as: snapshot. If you want a visual screenshot, use the screenshot tool instead.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'vmServiceUrl': {
          'type': 'string',
          'description':
              'VM Service WebSocket URL (optional — auto-discovers via mDNS if omitted)',
        },
      },
    },
    handler: (args) async {
      final conn = await factory.getConnection(args['vmServiceUrl'] as String?);
      return snapshotImpl(conn);
    },
  );
}
