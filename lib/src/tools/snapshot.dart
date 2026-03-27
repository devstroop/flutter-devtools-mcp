import '../connection.dart';
import '../transform.dart';

/// MCP tool: snapshot
///
/// Returns the current widget tree as LLM-friendly JSON.
/// Uses `getRootWidgetSummaryTree` (already pruned by Flutter).
Future<Map<String, Object?>> snapshotTool(FlutterConnection connection) async {
  final rawTree = await connection.callInspector(
    'getRootWidgetSummaryTree',
    {'objectGroup': 'mcp-snapshot'},
  );
  return transformTree(rawTree);
}
