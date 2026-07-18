import 'package:logging/logging.dart';

import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';
import '../actions.dart' as actions;

final _log = Logger('PressBack');

/// MCP tool: press_back
///
/// Pop the top route from the navigator stack.
Future<Map<String, Object?>> pressBackImpl(
  FlutterConnection connection,
) async {
  try {
    await actions.pressBack(connection);
    _log.info('Pressed back');
    return {'status': 'success'};
  } catch (e) {
    _log.warning('Press back failed: $e');
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
      return pressBackImpl(conn);
    },
  );
}
