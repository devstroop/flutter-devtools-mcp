import 'package:logging/logging.dart';

import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';
import '../selectors.dart';
import '../actions.dart' as actions;
import '../retry.dart';

final _log = Logger('Tap');

/// MCP tool: tap
///
/// Tap a widget identified by selector.
/// Flow: resolve selector → get bounds → check actionability → tap center.
Future<Map<String, Object?>> tapImpl(
  FlutterConnection connection,
  String selectorStr,
) async {
  try {
    final selector = Selector.parse(selectorStr);

    // Text and index selectors can hit deep widgets — use a longer
    // timeout to accommodate tree traversal + bounds resolution.
    final isTextOrIndex = selector.tier == SelectorTier.text ||
        selector.tier == SelectorTier.byIndex;
    final config = isTextOrIndex
        ? const RetryConfig(timeout: Duration(seconds: 8))
        : const RetryConfig();

    final result = await withRetry(() async {
      final node = await resolveSelector(connection, selector);
      final bounds = await actions.getBounds(connection, node);
      final check = await actions.checkActionability(connection, node, bounds);
      if (!check.actionable) {
        throw StateError('Not actionable: ${check.reason}');
      }
      await actions.tap(connection, bounds);
      return (node: node, bounds: bounds);
    }, description: 'tap($selectorStr)', config: config);

    _log.info('Tapped $selectorStr → ${result.node.type}');
    return {'status': 'success', 'node': result.node.toJson()};
  } catch (e) {
    _log.warning('Tap $selectorStr failed: $e');
    return {'status': 'error', 'error': e.toString()};
  }
}

/// Create an MCP [ToolDef] for tap.
ToolDef createTapTool() {
  return ToolDef(
    name: 'tap',
    description: 'Tap a widget identified by a CSS-style selector.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'selector': {
          'type': 'string',
          'description':
              'CSS-style selector identifying the widget to tap (e.g. "semantics:Increment", "text=Submit").',
        },
      },
      'required': ['selector'],
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      return tapImpl(conn, args['selector'] as String);
    },
  );
}
