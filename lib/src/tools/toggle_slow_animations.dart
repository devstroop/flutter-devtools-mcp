import 'package:logging/logging.dart';

import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';

final _log = Logger('ToggleSlowAnim');

/// MCP tool: toggle_slow_animations
///
/// Slow down or speed up animations by adjusting the time dilation factor.
Future<Map<String, Object?>> toggleSlowAnimationsImpl(
  FlutterConnection connection,
  double timeDilation,
) async {
  if (timeDilation <= 0) {
    return {
      'status': 'error',
      'error': 'Time dilation must be positive. Use 1.0 for normal speed.',
    };
  }

  try {
    final response = await connection.service.callServiceExtension(
      'ext.flutter.timeDilation',
      isolateId: connection.isolateId,
      args: {'timeDilation': timeDilation.toString()},
    );

    final current = response.json?['timeDilation'] as String?;
    final factor = current != null ? double.tryParse(current) : null;
    _log.info('Time dilation: ${factor ?? timeDilation}');

    return {
      'status': 'success',
      'timeDilation': factor ?? timeDilation,
      'message': timeDilation == 1.0
          ? 'Animations restored to normal speed.'
          : 'Animations slowed to $timeDilation× dilation.',
    };
  } catch (e) {
    _log.warning('Toggle slow animations failed: $e');
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createToggleSlowAnimationsTool() {
  return ToolDef(
    name: 'toggle_slow_animations',
    description:
        'Slow down or restore animation speed. 1.0 = normal, 2.0 = 2× slower, 5.0 = 5× slower.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'timeDilation': {
          'type': 'number',
          'description': 'Time dilation factor (1.0 = normal speed)'
        },
      },
      'required': ['timeDilation'],
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      return toggleSlowAnimationsImpl(
          conn, (args['timeDilation'] as num).toDouble());
    },
  );
}
