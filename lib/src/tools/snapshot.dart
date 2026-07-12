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

/// MCP tool: snapshot
///
/// Returns the current widget tree as LLM-friendly JSON.
/// Uses `getRootWidgetSummaryTree` (already pruned by Flutter).
ToolDef createSnapshotTool(ConnectionFactory factory) {
  return ToolDef(
    name: 'snapshot',
    description: 'Get the current widget tree as LLM-friendly JSON. '
        'Returns pruned tree with type, label, key, bounds for each node.',
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
      final conn = await factory.getConnection(args['vmServiceUrl']);
      return snapshotImpl(conn);
    },
  );
}
