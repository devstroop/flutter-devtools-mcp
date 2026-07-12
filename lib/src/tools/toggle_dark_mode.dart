import '../connection.dart';
import '../trace.dart';
import '../connection_factory.dart';
import '../mcp_transport.dart';

/// MCP tool: toggle_dark_mode
///
/// Toggle between light and dark mode using the Flutter brightness override.
/// Pass [enable] = true for dark mode, false for light mode, or null to
/// remove the override (revert to system default).
Future<Map<String, Object?>> toggleDarkModeImpl(
  FlutterConnection connection,
  bool? enable,
  TraceLog trace,
) async {
  final startTime = trace.start();

  try {
    final response = await connection.service.callServiceExtension(
      'ext.flutter.brightnessOverride',
      isolateId: connection.isolateId,
      args: {
        if (enable != null)
          'value': enable ? 'Brightness.dark' : 'Brightness.light'
        else
          'value': 'Brightness.light', // remove override by setting light
      },
    );

    // Read back the current value
    final current = response.json?['value'] as String?;

    trace.complete(
      action: 'toggle_dark_mode',
      startTimeMs: startTime,
      target: enable?.toString() ?? 'system',
      result: 'success',
    );

    return {
      'status': 'success',
      'darkMode': current?.contains('dark') ?? enable ?? false,
      'brightness':
          current ?? (enable == true ? 'Brightness.dark' : 'Brightness.light'),
    };
  } catch (e) {
    trace.complete(
      action: 'toggle_dark_mode',
      startTimeMs: startTime,
      result: 'error',
      error: e.toString(),
    );
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createToggleDarkModeTool(ConnectionFactory factory) {
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
        'vmServiceUrl': {
          'type': 'string',
          'description':
              'VM Service WebSocket URL (optional — auto-discovers via mDNS if omitted)'
        },
      },
      'required': ['enable'],
    },
    handler: (args) async {
      final conn = await factory.getConnection(args['vmServiceUrl'] as String?);
      return toggleDarkModeImpl(conn, args['enable'] as bool, TraceLog());
    },
  );
}
