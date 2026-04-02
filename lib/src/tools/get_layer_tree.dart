import '../connection.dart';
import '../trace.dart';

/// MCP tool: get_layer_tree
///
/// Dump the compositing layer tree as text. Shows how Flutter composes
/// render objects into layers for GPU rendering. Useful for diagnosing
/// compositing issues, saveLayer calls, and opacity/clip layer overhead.
Future<Map<String, Object?>> getLayerTreeTool(
  FlutterConnection connection,
  TraceLog trace,
) async {
  final startTime = trace.start();

  try {
    final response = await connection.service.callServiceExtension(
      'ext.flutter.debugDumpLayerTree',
      isolateId: connection.isolateId,
    );

    final dump = response.json?['data'] as String?;

    trace.complete(
      action: 'get_layer_tree',
      startTimeMs: startTime,
      result: 'success',
    );

    return {
      'status': 'success',
      'layerTree': dump ?? response.json?.toString() ?? 'No data returned',
    };
  } catch (e) {
    trace.complete(
      action: 'get_layer_tree',
      startTimeMs: startTime,
      result: 'error',
      error: e.toString(),
    );
    return {'status': 'error', 'error': e.toString()};
  }
}
