import 'package:logging/logging.dart';

import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';

final _log = Logger('TogglePerfOverlay');

/// MCP tool: toggle_performance_overlay
///
/// Toggle the Flutter performance overlay — shows real-time frame timing
/// graphs (UI thread and raster thread).
Future<Map<String, Object?>> togglePerformanceOverlayImpl(
  FlutterConnection connection,
  bool enable,
) async {
  try {
    final response = await connection.service.callServiceExtension(
      'ext.flutter.showPerformanceOverlay',
      isolateId: connection.isolateId,
      args: {'enabled': enable.toString()},
    );

    final current = response.json?['enabled'] as String?;
    _log.info(
        'Performance overlay: ${(current ?? enable.toString()) == 'true'}');

    return {
      'status': 'success',
      'performanceOverlay': (current ?? enable.toString()) == 'true',
      'message': enable
          ? 'Performance overlay enabled. Take a screenshot to see frame timing graphs.'
          : 'Performance overlay disabled.',
    };
  } catch (e) {
    _log.warning('Toggle performance overlay failed: $e');
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createTogglePerformanceOverlayTool() {
  return ToolDef(
    name: 'toggle_performance_overlay',
    description:
        'Toggle the Flutter performance overlay — shows real-time frame timing graphs (UI thread and raster thread).',
    inputSchema: {
      'type': 'object',
      'properties': {
        'enable': {
          'type': 'boolean',
          'description': 'true to show performance overlay, false to hide'
        },
      },
      'required': ['enable'],
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      return togglePerformanceOverlayImpl(conn, args['enable'] as bool);
    },
  );
}
