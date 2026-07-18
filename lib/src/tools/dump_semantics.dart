import 'package:logging/logging.dart';

import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';

final _log = Logger('DumpSemantics');

/// MCP tool: dump_semantics
///
/// Dump the accessibility (semantics) tree in traversal order.
/// Useful for verifying accessibility labels, roles, and screen reader output.
Future<Map<String, Object?>> dumpSemanticsImpl(
  FlutterConnection connection,
) async {
  try {
    final response = await connection.service.callServiceExtension(
      'ext.flutter.debugDumpSemanticsTreeInTraversalOrder',
      isolateId: connection.isolateId,
    );

    final dump = response.json?['data'] as String?;
    _log.info('Semantics tree dumped (${dump?.length ?? 0} chars)');

    return {
      'status': 'success',
      'semanticsTree': dump ?? response.json?.toString() ?? 'No data returned',
    };
  } catch (e) {
    _log.warning('Dump semantics failed: $e');
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createDumpSemanticsTool() {
  return ToolDef(
    name: 'dump_semantics',
    description: 'Dump the accessibility (semantics) tree in traversal order.',
    inputSchema: {
      'type': 'object',
      'properties': {},
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      return dumpSemanticsImpl(conn);
    },
  );
}
