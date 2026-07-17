import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';
import '../actions.dart' as actions;
import '../trace.dart';

/// MCP tool: press_back
///
/// Pop the top route from the navigator stack.
Future<Map<String, Object?>> pressBackImpl(
  FlutterConnection connection,
  TraceLog trace,
) async {
  final startTime = trace.start();

  try {
    await actions.pressBack(connection);

    trace.complete(
      action: 'press_back',
      startTimeMs: startTime,
      result: 'success',
    );

    return {'status': 'success'};
  } catch (e) {
    trace.complete(
      action: 'press_back',
      startTimeMs: startTime,
      result: 'error',
      error: e.toString(),
    );

    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createPressBackTool() {
  return ToolDef(
    name: 'press_back',
    description: 'Pop the top route from the navigator stack.',
    inputSchema: {
      'type': 'object',
      'properties': {},
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      return pressBackImpl(conn, TraceLog());
    },
  );
}
