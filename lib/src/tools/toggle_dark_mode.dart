import '../connection.dart';
import '../trace.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';

/// MCP tool: toggle_dark_mode
///
/// Toggle between light and dark mode using the Flutter brightness override.
/// Pass [enable] = true for dark mode, false for light mode.
Future<Map<String, Object?>> toggleDarkModeImpl(
  FlutterConnection connection,
  bool enable,
  TraceLog trace,
) async {
  final startTime = trace.start();

  try {
    final response = await connection.service.callServiceExtension(
      'ext.flutter.brightnessOverride',
      isolateId: connection.isolateId,
      args: {
        'value': enable ? 'Brightness.dark' : 'Brightness.light',
      },
    );

    // Read back the current value
    final current = response.json?['value'] as String?;

    trace.complete(
      action: 'toggle_dark_mode',
      startTimeMs: startTime,
      target: enable.toString(),
      result: 'success',
    );

    return {
      'status': 'success',
      'darkMode': current?.contains('dark') ?? enable,
      'brightness':
          current ?? (enable ? 'Brightness.dark' : 'Brightness.light'),
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
      return toggleDarkModeImpl(conn, args['enable'] as bool, TraceLog());
    },
  );
}
