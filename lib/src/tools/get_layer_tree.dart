import 'package:logging/logging.dart';

import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';

final _log = Logger('GetLayerTree');

/// MCP tool: get_layer_tree
///
/// Dump the compositing layer tree as text. Shows how Flutter composes
/// render objects into layers for GPU rendering.
Future<Map<String, Object?>> getLayerTreeImpl(
  FlutterConnection connection,
) async {
  try {
    final response = await connection.service.callServiceExtension(
      'ext.flutter.debugDumpLayerTree',
      isolateId: connection.isolateId,
    );

    final dump = response.json?['data'] as String?;
    _log.info('Layer tree dumped (${dump?.length ?? 0} chars)');

    return {
      'status': 'success',
      'layerTree': dump ?? response.json?.toString() ?? 'No data returned',
    };
  } catch (e) {
    _log.warning('Get layer tree failed: $e');
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createGetLayerTreeTool() {
  return ToolDef(
    name: 'get_layer_tree',
    description: 'Dump the compositing layer tree as text.',
    inputSchema: {
      'type': 'object',
      'properties': {},
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      return getLayerTreeImpl(conn);
    },
  );
}
