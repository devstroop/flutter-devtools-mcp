import 'package:logging/logging.dart';

import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';

final _log = Logger('ToggleDarkMode');

/// MCP tool: toggle_dark_mode
///
/// Toggle between light and dark mode using the Flutter brightness override.
Future<Map<String, Object?>> toggleDarkModeImpl(
  FlutterConnection connection,
  bool enable,
) async {
  try {
    final response = await connection.service.callServiceExtension(
      'ext.flutter.brightnessOverride',
      isolateId: connection.isolateId,
      args: {
        'value': enable ? 'Brightness.dark' : 'Brightness.light',
      },
    );

    final current = response.json?['value'] as String?;
    _log.info('Dark mode: ${current ?? enable}');

    return {
      'status': 'success',
      'darkMode': current?.contains('dark') ?? enable,
      'brightness':
          current ?? (enable ? 'Brightness.dark' : 'Brightness.light'),
    };
  } catch (e) {
    _log.warning('Toggle dark mode failed: $e');
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createToggleDarkModeTool() {
  return ToolDef(
    name: 'toggle_dark_mode',
    description:
        'Toggle between light and dark mode using the Flutter brightness override.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'enable': {
          'type': 'boolean',
          'description': 'true for dark mode, false for light mode'
        },
      },
      'required': ['enable'],
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      return toggleDarkModeImpl(conn, args['enable'] as bool);
    },
  );
}
