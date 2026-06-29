import '../connection.dart';
import '../connection_factory.dart';
import '../mcp_transport.dart';
import '../trace.dart';

/// MCP tool: dump_semantics
///
/// Dump the accessibility (semantics) tree in traversal order.
/// Useful for verifying accessibility labels, roles, and screen reader output.
Future<Map<String, Object?>> dumpSemanticsImpl(
  FlutterConnection connection,
  TraceLog trace,
) async {
  final startTime = trace.start();

  try {
    final response = await connection.service.callServiceExtension(
      'ext.flutter.debugDumpSemanticsTreeInTraversalOrder',
      isolateId: connection.isolateId,
    );

    final dump = response.json?['data'] as String?;

    trace.complete(
      action: 'dump_semantics',
      startTimeMs: startTime,
      result: 'success',
    );

    return {
      'status': 'success',
      'semanticsTree': dump ?? response.json?.toString() ?? 'No data returned',
    };
  } catch (e) {
    trace.complete(
      action: 'dump_semantics',
      startTimeMs: startTime,
      result: 'error',
      error: e.toString(),
    );
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createDumpSemanticsTool(ConnectionFactory factory) {
  return ToolDef(
    name: 'dump_semantics',
    description: 'Dump the accessibility (semantics) tree in traversal order.',
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
      final conn = await factory.getConnection(args['vmServiceUrl'] as String?);
      return dumpSemanticsImpl(conn, TraceLog());
    },
  );
}
