import 'package:logging/logging.dart';

import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';

final _log = Logger('Evaluate');

/// MCP tool impl: evaluate
///
/// Evaluate a Dart expression in the running app's main isolate.
/// Returns the string representation of the result.
Future<Map<String, Object?>> evaluateImpl(
  FlutterConnection connection,
  String expression,
) async {
  try {
    final result = await connection.evaluate(expression);
    _log.fine(
        'Evaluated: ${expression.length > 64 ? '${expression.substring(0, 64)}...' : expression} → ${result.valueAsString}');
    return {
      'status': 'success',
      'value': result.valueAsString,
      'type': result.classRef?.name,
    };
  } catch (e) {
    _log.warning('Evaluate failed: $e');
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
        'expression': {
          'type': 'string',
          'description': 'Dart expression to evaluate'
        },
      },
      'required': ['expression'],
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      return evaluateImpl(conn, args['expression'] as String);
    },
  );
}
