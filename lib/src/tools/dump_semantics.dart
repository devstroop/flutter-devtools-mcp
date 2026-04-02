import '../connection.dart';
import '../trace.dart';

/// MCP tool: dump_semantics
///
/// Dump the accessibility (semantics) tree in traversal order.
/// Useful for verifying accessibility labels, roles, and screen reader output.
Future<Map<String, Object?>> dumpSemanticsTool(
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
