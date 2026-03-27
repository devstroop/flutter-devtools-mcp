import '../connection.dart';
import '../transform.dart';

/// MCP tool: snapshot
///
/// Returns the current widget tree as LLM-friendly JSON.
/// Uses `getRootWidgetSummaryTree` (already pruned by Flutter).
Future<Map<String, Object?>> snapshotTool(FlutterConnection connection) async {
  final response = await connection.callInspector(
    'getRootWidgetSummaryTree',
    {'groupName': 'mcp-snapshot'},
  );
  final rawTree = response.json!;
  return transformTree(rawTree);
}
