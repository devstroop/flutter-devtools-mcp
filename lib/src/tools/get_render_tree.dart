import '../connection.dart';
import '../trace.dart';

/// MCP tool: get_render_tree
///
/// Dump the full render object tree as text. Shows the RenderObject hierarchy
/// with layout constraints, sizes, and paint information. Complements the
/// widget tree snapshot with lower-level rendering details.
Future<Map<String, Object?>> getRenderTreeTool(
  FlutterConnection connection,
  TraceLog trace,
) async {
  final startTime = trace.start();

  try {
    final response = await connection.service.callServiceExtension(
      'ext.flutter.debugDumpRenderTree',
      isolateId: connection.isolateId,
    );

    final dump = response.json?['data'] as String?;

    trace.complete(
      action: 'get_render_tree',
      startTimeMs: startTime,
      result: 'success',
    );

    return {
      'status': 'success',
      'renderTree': dump ?? response.json?.toString() ?? 'No data returned',
    };
  } catch (e) {
    trace.complete(
      action: 'get_render_tree',
      startTimeMs: startTime,
      result: 'error',
      error: e.toString(),
    );
    return {'status': 'error', 'error': e.toString()};
  }
}
