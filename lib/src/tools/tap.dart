import '../connection.dart';
import '../connection_factory.dart';
import '../mcp_transport.dart';
import '../selectors.dart';
import '../actions.dart' as actions;
import '../retry.dart';
import '../trace.dart';

/// MCP tool: tap
///
/// Tap a widget identified by selector.
/// Flow: resolve selector → get bounds → check actionability → tap center.
Future<Map<String, Object?>> tapImpl(
  FlutterConnection connection,
  String selectorStr,
  TraceLog trace,
) async {
  final startTime = trace.start();
  var retryCount = 0;

  try {
    final selector = Selector.parse(selectorStr);

    final result = await withRetry(() async {
      retryCount++;
      final node = await resolveSelector(connection, selector);
      final bounds = await actions.getBounds(connection, node);
      final check = await actions.checkActionability(connection, node, bounds);
      if (!check.actionable) {
        throw StateError('Not actionable: ${check.reason}');
      }
      await actions.tap(connection, bounds);
      return (node: node, bounds: bounds);
    }, description: 'tap($selectorStr)');

    trace.complete(
      action: 'tap',
      startTimeMs: startTime,
      target: selectorStr,
      selector: selectorStr,
      resolvedNode: result.node.toJson(),
      bounds: result.bounds.toJson(),
      retryCount: retryCount - 1,
      result: 'success',
    );

    return {'status': 'success', 'node': result.node.toJson()};
  } catch (e) {
    trace.complete(
      action: 'tap',
      startTimeMs: startTime,
      target: selectorStr,
      selector: selectorStr,
      retryCount: retryCount,
      result: 'error',
      error: e.toString(),
    );
    return {'status': 'error', 'error': e.toString()};
  }
}

/// Create an MCP [ToolDef] for tap.
ToolDef createTapTool(ConnectionFactory factory) {
  return ToolDef(
    name: 'tap',
    description: 'Tap a widget identified by a CSS-style selector.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'selector': {
          'type': 'string',
          'description': 'CSS-style selector identifying the widget to tap (e.g. "semantics:Increment", "text=Submit").',
        },
        'vmServiceUrl': {
          'type': 'string',
          'description': 'Optional VM Service WebSocket URL to target a specific Flutter debug app.',
        },
      },
      'required': ['selector'],
    },
    handler: (args) async {
      final conn = await factory.getConnection(args['vmServiceUrl'] as String?);
      return tapImpl(conn, args['selector'] as String, TraceLog());
    },
  );
}
