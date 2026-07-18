import 'package:logging/logging.dart';

import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';

final _log = Logger('GetRenderTree');

/// MCP tool: get_render_tree
///
/// Dump the full render object tree as text. Shows the RenderObject hierarchy
/// with layout constraints, sizes, and paint information.
Future<Map<String, Object?>> getRenderTreeImpl(
  FlutterConnection connection,
) async {
  try {
    final response = await connection.service.callServiceExtension(
      'ext.flutter.debugDumpRenderTree',
      isolateId: connection.isolateId,
    );

    final dump = response.json?['data'] as String?;
    _log.info('Render tree dumped (${dump?.length ?? 0} chars)');

    return {
      'status': 'success',
      'renderTree': dump ?? response.json?.toString() ?? 'No data returned',
    };
  } catch (e) {
    _log.warning('Get render tree failed: $e');
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createGetRenderTreeTool() {
  return ToolDef(
    name: 'get_render_tree',
    description: 'Dump the full render object tree as text.',
    inputSchema: {
      'type': 'object',
      'properties': {},
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      return getRenderTreeImpl(conn);
    },
  );
}
