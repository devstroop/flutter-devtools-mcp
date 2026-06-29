import '../connection.dart';
import '../connection_factory.dart';
import '../mcp_transport.dart';
import '../trace.dart';

/// MCP tool: get_layer_tree
///
/// Dump the compositing layer tree as text. Shows how Flutter composes
/// render objects into layers for GPU rendering. Useful for diagnosing
/// compositing issues, saveLayer calls, and opacity/clip layer overhead.
Future<Map<String, Object?>> getLayerTreeImpl(
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

ToolDef createGetLayerTreeTool(ConnectionFactory factory) {
  return ToolDef(
    name: 'get_layer_tree',
    description: 'Dump the compositing layer tree as text.',
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
      return getLayerTreeImpl(conn, TraceLog());
    },
  );
}
