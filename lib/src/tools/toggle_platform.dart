import '../connection.dart';
import '../trace.dart';

/// MCP tool: toggle_platform
///
/// Override the target platform for the Flutter app.
/// Accepts: 'android', 'ios', 'fuchsia', 'linux', 'macOS', 'windows'.
Future<Map<String, Object?>> togglePlatformTool(
  FlutterConnection connection,
  String platform,
  TraceLog trace,
) async {
  final startTime = trace.start();

  // Map user-friendly names to TargetPlatform enum values
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
    trace.complete(
      action: 'toggle_platform',
      startTimeMs: startTime,
      target: platform,
      result: 'error',
      error: 'Invalid platform',
    );
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

    trace.complete(
      action: 'toggle_platform',
      startTimeMs: startTime,
      target: platform,
      result: 'success',
    );

    return {
      'status': 'success',
      'platform': current ?? enumValue,
    };
  } catch (e) {
    trace.complete(
      action: 'toggle_platform',
      startTimeMs: startTime,
      target: platform,
      result: 'error',
      error: e.toString(),
    );
    return {'status': 'error', 'error': e.toString()};
  }
}
