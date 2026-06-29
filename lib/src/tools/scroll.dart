import '../connection.dart';
import '../connection_factory.dart';
import '../mcp_transport.dart';
import '../selectors.dart';
import '../actions.dart' as actions;
import '../retry.dart';
import '../trace.dart';

/// MCP tool: scroll
///
/// Scroll a scrollable widget in a direction.
Future<Map<String, Object?>> scrollImpl(
  FlutterConnection connection,
  String selectorStr,
  String direction, // 'up', 'down', 'left', 'right'
  TraceLog trace, {
  double amount = 300.0,
}) async {
  final startTime = trace.start();

  final (dx, dy) = switch (direction) {
    'up' => (0.0, amount),
    'down' => (0.0, -amount),
    'left' => (amount, 0.0),
    'right' => (-amount, 0.0),
    _ => throw ArgumentError('Invalid direction: $direction. Use up/down/left/right.'),
  };

  try {
    final selector = Selector.parse(selectorStr);

    await withRetry(() async {
      final node = await resolveSelector(connection, selector);
      final bounds = await actions.getBounds(connection, node);
      await actions.scroll(connection, bounds, dx: dx, dy: dy);
    }, description: 'scroll($selectorStr, $direction)');

    trace.complete(
      action: 'scroll',
      startTimeMs: startTime,
      target: '$selectorStr ($direction)',
      selector: selectorStr,
      result: 'success',
    );

    return {'status': 'success', 'direction': direction, 'amount': amount};
  } catch (e) {
    trace.complete(
      action: 'scroll',
      startTimeMs: startTime,
      target: selectorStr,
      selector: selectorStr,
      result: 'error',
      error: e.toString(),
    );
    return {'status': 'error', 'error': e.toString()};
  }
}

/// Create an MCP [ToolDef] for scroll.
ToolDef createScrollTool(ConnectionFactory factory) {
  return ToolDef(
    name: 'scroll',
    description: 'Scroll a scrollable widget in a given direction.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'selector': {
          'type': 'string',
          'description': 'CSS-style selector identifying the scrollable widget.',
        },
        'direction': {
          'type': 'string',
          'enum': ['up', 'down', 'left', 'right'],
          'description': 'Direction to scroll.',
        },
        'amount': {
          'type': 'number',
          'description': 'Amount to scroll in logical pixels (default: 300).',
        },
        'vmServiceUrl': {
          'type': 'string',
          'description': 'Optional VM Service WebSocket URL to target a specific Flutter debug app.',
        },
      },
      'required': ['selector', 'direction'],
    },
    handler: (args) async {
      final conn = await factory.getConnection(args['vmServiceUrl'] as String?);
      return scrollImpl(
        conn,
        args['selector'] as String,
        args['direction'] as String,
        TraceLog(),
        amount: (args['amount'] as num?)?.toDouble() ?? 300.0,
      );
    },
  );
}
