import '../connection.dart';
import '../actions.dart' as actions;
import '../trace.dart';

/// MCP tool: press_back
///
/// Pop the top route from the navigator stack.
Future<Map<String, Object?>> pressBackTool(
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
