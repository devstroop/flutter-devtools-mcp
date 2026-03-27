import '../connection.dart';
import '../selectors.dart';
import '../actions.dart' as actions;
import '../retry.dart';
import '../trace.dart';

/// MCP tool: type_text
///
/// Focus a text field by selector, then enter text.
Future<Map<String, Object?>> typeTextTool(
  FlutterConnection connection,
  String selectorStr,
  String text,
  TraceLog trace,
) async {
  final startTime = trace.start();

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

    trace.complete(
      action: 'type_text',
      startTimeMs: startTime,
      target: selectorStr,
      selector: selectorStr,
      result: 'success',
    );

    return {'status': 'success', 'text': text};
  } catch (e) {
    trace.complete(
      action: 'type_text',
      startTimeMs: startTime,
      target: selectorStr,
      selector: selectorStr,
      result: 'error',
      error: e.toString(),
    );
    rethrow;
  }
}
