import '../connection.dart';
import '../transform.dart';

/// MCP tool: inspect
///
/// Get detailed properties of a specific widget node by its ID.
/// Uses `getDetailsSubtree` for deep property enrichment.
Future<Map<String, Object?>> inspectTool(
  FlutterConnection connection,
  String nodeId,
) async {
  final response = await connection.callInspector(
    'getDetailsSubtree',
    {
      'objectGroup': 'mcp-inspect',
      'arg': nodeId,
      'subtreeDepth': '2',
    },
  );
  final rawNode = response.json!;
  return transformTree(rawNode);
}
