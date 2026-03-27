import '../connection.dart';
import '../trace.dart';

/// MCP tool: evaluate
///
/// Evaluate a Dart expression in the running app's main isolate.
/// Returns the string representation of the result.
Future<Map<String, Object?>> evaluateTool(
  FlutterConnection connection,
  String expression,
  TraceLog trace,
) async {
  final startTime = trace.start();

  try {
    final result = await connection.evaluate(expression);

    trace.complete(
      action: 'evaluate',
      startTimeMs: startTime,
      target: expression,
      result: 'success',
    );

    return {
      'status': 'success',
      'value': result.valueAsString,
      'type': result.classRef?.name,
    };
  } catch (e) {
    trace.complete(
      action: 'evaluate',
      startTimeMs: startTime,
      target: expression,
      result: 'error',
      error: e.toString(),
    );
    return {'status': 'error', 'error': e.toString()};
  }
}
