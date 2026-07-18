import 'package:logging/logging.dart';

import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';

final _log = Logger('TogglePlatform');

/// MCP tool impl: toggle_platform
///
/// Override the target platform for the Flutter app.
Future<Map<String, Object?>> togglePlatformImpl(
  FlutterConnection connection,
  String platform,
) async {
  final platformMap = {
    'android': 'android',
    'ios': 'iOS',
    'fuchsia': 'fuchsia',
    'linux': 'linux',
    'macos': 'macOS',
    'windows': 'windows',
  };

  final enumValue = platformMap[platform.toLowerCase()];
  if (enumValue == null) {
    return {
      'status': 'error',
      'error': 'Invalid platform "$platform". '
          'Valid values: ${platformMap.keys.join(", ")}',
    };
  }

  try {
    final response = await connection.service.callServiceExtension(
      'ext.flutter.platformOverride',
      isolateId: connection.isolateId,
      args: {'value': enumValue},
    );

    final current = response.json?['value'] as String?;
    _log.info('Platform: ${current ?? enumValue}');

    return {
      'status': 'success',
      'platform': current ?? enumValue,
    };
  } catch (e) {
    _log.warning('Toggle platform failed: $e');
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createTogglePlatformTool() {
  return ToolDef(
    name: 'toggle_platform',
    description: 'Override the target platform for the Flutter app.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'platform': {
          'type': 'string',
          'description': 'Target platform',
          'enum': ['android', 'ios', 'fuchsia', 'linux', 'macos', 'windows'],
        },
      },
      'required': ['platform'],
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      return togglePlatformImpl(conn, args['platform'] as String);
    },
  );
}
