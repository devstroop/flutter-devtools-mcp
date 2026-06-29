import '../connection.dart';
import '../trace.dart';
import '../connection_factory.dart';
import '../mcp_transport.dart';

/// MCP tool: toggle_slow_animations
///
/// Slow down or speed up animations by adjusting the time dilation factor.
/// A factor of 1.0 is normal speed, 2.0 is half speed, 5.0 is 5× slower, etc.
/// Useful for debugging animation issues or verifying transition behavior.
Future<Map<String, Object?>> toggleSlowAnimationsImpl(
  FlutterConnection connection,
  double timeDilation,
  TraceLog trace,
) async {
  final startTime = trace.start();

  if (timeDilation <= 0) {
    trace.complete(
      action: 'toggle_slow_animations',
      startTimeMs: startTime,
      result: 'error',
      error: 'Invalid time dilation',
    );
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

    trace.complete(
      action: 'toggle_slow_animations',
      startTimeMs: startTime,
      target: timeDilation.toString(),
      result: 'success',
    );

    return {
      'status': 'success',
      'timeDilation': factor ?? timeDilation,
      'message': timeDilation == 1.0
          ? 'Animations restored to normal speed.'
          : 'Animations slowed to $timeDilation× dilation.',
    };
  } catch (e) {
    trace.complete(
      action: 'toggle_slow_animations',
      startTimeMs: startTime,
      result: 'error',
      error: e.toString(),
    );
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createToggleSlowAnimationsTool(ConnectionFactory factory) {
  return ToolDef(
    name: 'toggle_slow_animations',
    description: 'Slow down or restore animation speed. 1.0 = normal, 2.0 = 2× slower, 5.0 = 5× slower.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'timeDilation': {'type': 'number', 'description': 'Time dilation factor (1.0 = normal speed)'},
        'vmServiceUrl': {'type': 'string', 'description': 'VM Service WebSocket URL (optional — auto-discovers via mDNS if omitted)'},
      },
      'required': ['timeDilation'],
    },
    handler: (args) async {
      final conn = await factory.getConnection(args['vmServiceUrl']);
      return toggleSlowAnimationsImpl(conn, (args['timeDilation'] as num).toDouble(), TraceLog());
    },
  );
}
