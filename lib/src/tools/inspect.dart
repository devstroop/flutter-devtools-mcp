import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';
import '../transform.dart';

/// MCP tool impl: inspect
///
/// Get detailed properties of a specific widget node by its ID.
/// Uses `getDetailsSubtree` for deep property enrichment.
Future<Map<String, Object?>> inspectImpl(
  FlutterConnection connection,
  String nodeId,
) async {
  final rawNode = await connection.callInspector(
    'getDetailsSubtree',
    {
      'objectGroup': 'mcp-inspect',
      'arg': nodeId,
      'subtreeDepth': '2',
    },
  );
  return transformTree(rawNode);
}

ToolDef createInspectTool() {
  return ToolDef(
    name: 'inspect',
    description: 'Get detailed properties of a specific widget node.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'nodeId': {'type': 'string', 'description': 'Node ID from snapshot'},
      },
      'required': ['nodeId'],
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      return inspectImpl(conn, args['nodeId'] as String);
    },
  );
}
