import 'package:logging/logging.dart';

import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';
import '../selectors.dart';
import '../actions.dart' as actions;
import '../retry.dart';

final _log = Logger('TypeText');

/// MCP tool: type_text
///
/// Focus a text field by selector, then enter text.
Future<Map<String, Object?>> typeTextImpl(
  FlutterConnection connection,
  String selectorStr,
  String text,
) async {
  try {
    final selector = Selector.parse(selectorStr);

    await withRetry(() async {
      final node = await resolveSelector(connection, selector);
      final bounds = await actions.getBounds(connection, node);
      // Tap to focus the field first
      await actions.tap(connection, bounds);
    }, description: 'focus($selectorStr)');

    // Small delay for focus to settle
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await actions.enterText(connection, text);
    _log.info('Typed text into $selectorStr');
    return {'status': 'success', 'text': text};
  } catch (e) {
    _log.warning('Type text into $selectorStr failed: $e');
    return {'status': 'error', 'error': e.toString()};
  }
}

/// Create an MCP [ToolDef] for type_text.
ToolDef createTypeTextTool() {
  return ToolDef(
    name: 'type_text',
    description: 'Focus a text field by selector, then enter text.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'selector': {
          'type': 'string',
          'description':
              'CSS-style selector identifying the text field (e.g. "semantics:textField", "text=Email").',
        },
        'text': {
          'type': 'string',
          'description': 'Text to type into the field.',
        },
      },
      'required': ['selector', 'text'],
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      return typeTextImpl(
          conn, args['selector'] as String, args['text'] as String);
    },
  );
}
