import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';
import '../trace.dart';

/// MCP tool impl: evaluate
///
/// Evaluate a Dart expression in the running app's main isolate.
/// Returns the string representation of the result.
Future<Map<String, Object?>> evaluateImpl(
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

ToolDef createEvaluateTool() {
  return ToolDef(
    name: 'evaluate',
    description: 'Evaluate a Dart expression in the running app.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'expression': {'type': 'string', 'description': 'Dart expression to evaluate'},
      },
      'required': ['expression'],
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      return evaluateImpl(conn, args['expression'] as String, TraceLog());
    },
  );
}
