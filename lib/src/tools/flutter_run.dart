import 'dart:convert';
import 'dart:io';

import '../current_connection.dart';
import '../mcp_transport.dart';
import '../registry.dart';
import '../managed_run.dart';

/// MCP tool: flutter_run
///
/// Start a Flutter app in debug mode and auto-connect to its VM Service.
/// No need to manually copy-paste the VM Service URL — the server captures
/// it automatically from the `flutter run --debug` output.
ToolDef createFlutterRunTool() {
  return ToolDef(
    name: 'flutter_run',
    description: 'Start a Flutter app in debug mode and auto-connect. '
        'Runs `flutter run --debug` for the given platform, captures the '
        'VM Service URL automatically, and connects. '
        'Use this instead of manually running `flutter run` and pasting URLs.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'platform': {
          'type': 'string',
          'description':
              'Target platform: macos, ios, android, linux, windows, web.',
          'enum': ['macos', 'ios', 'android', 'linux', 'windows', 'web'],
        },
        'workingDirectory': {
          'type': 'string',
          'description':
              'Path to the Flutter project root. Defaults to the current '
                  'working directory.',
        },
      },
      'required': ['platform'],
    },
    handler: (args) async {
      final platform = args['platform'] as String;
      final workingDir =
          args['workingDirectory'] as String? ?? Directory.current.path;

      // When the flutter run process exits unexpectedly (crash, user
      // quitting the app, etc.), disconnect cleanly.
      ManagedFlutterRun.onUnexpectedExit = (exitCode) {
        CurrentConnection.disconnect();
      };

      try {
        final conn = await ManagedFlutterRun.start(
          workingDirectory: workingDir,
          platform: platform,
        );
        await CurrentConnection.set(conn);
        Registry.instance.register(conn.vmServiceUrl);
        return {
          'content': [
            {
              'type': 'text',
              'text': json.encode({
                'status': 'connected',
                'url': conn.vmServiceUrl,
                'platform': platform,
                'project': workingDir,
              }),
            },
          ],
        };
      } catch (e) {
        return {
          'isError': true,
          'content': [
            {
              'type': 'text',
              'text': 'Failed to start flutter run: $e',
            },
          ],
        };
      }
    },
  );
}
