import 'dart:convert';
import 'dart:io';

import '../current_connection.dart';
import '../mcp_transport.dart';
import '../registry.dart';
import '../managed_run.dart';

/// Shared handler for all run/launch tool aliases.
Future<Map<String, dynamic>> _runHandler(Map<String, dynamic> args) async {
  final platform = args['platform'] as String?;
  if (platform == null || platform.isEmpty) {
    return {
      'isError': true,
      'content': [
        {
          'type': 'text',
          'text':
              'platform is required (macos, ios, android, linux, windows, web).',
        },
      ],
    };
  }

  final workingDir =
      args['workingDirectory'] as String? ?? Directory.current.path;

  ManagedFlutterRun.onUnexpectedExit = (exitCode) {
    CurrentConnection.disconnect();
  };

  try {
    final conn = await ManagedFlutterRun.start(
      workingDirectory: workingDir,
      platform: platform,
    );
    await CurrentConnection.set(conn);
    // Registry persistence is best-effort — a failure here should not
    // cause the connection to be dropped.
    try {
      Registry.instance.register(conn.vmServiceUrl);
    } catch (e) {
      stderr.writeln('[flutter_run] Failed to register URL: $e');
    }
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
}

/// MCP tool: launch (canonical name)
///
/// Start a Flutter app in debug mode and auto-connect to its VM Service.
ToolDef createLaunchTool() {
  return ToolDef(
    name: 'launch',
    description: 'Start a Flutter app in debug mode and auto-connect. '
        'Runs `flutter run --debug` for the given platform, captures the '
        'VM Service URL automatically, and connects. '
        'Aliases: run, flutter_run.',
    inputSchema: _inputSchema(),
    handler: _runHandler,
  );
}

/// MCP tool: run (alias for launch)
ToolDef createRunTool() {
  return ToolDef(
    name: 'run',
    description: 'Start a Flutter app in debug mode and auto-connect. '
        'Alias for launch.',
    inputSchema: _inputSchema(),
    handler: _runHandler,
  );
}

/// MCP tool: flutter_run (alias for launch)
ToolDef createFlutterRunTool() {
  return ToolDef(
    name: 'flutter_run',
    description: 'Start a Flutter app in debug mode and auto-connect. '
        'Alias for launch.',
    inputSchema: _inputSchema(),
    handler: _runHandler,
  );
}

/// MCP tool: launch_app (alias for launch)
ToolDef createLaunchAppTool() {
  return ToolDef(
    name: 'launch_app',
    description: 'Start a Flutter app in debug mode and auto-connect. '
        'Alias for launch.',
    inputSchema: _inputSchema(),
    handler: _runHandler,
  );
}

/// MCP tool: start_app (alias for launch)
ToolDef createStartAppTool() {
  return ToolDef(
    name: 'start_app',
    description: 'Start a Flutter app in debug mode and auto-connect. '
        'Alias for launch.',
    inputSchema: _inputSchema(),
    handler: _runHandler,
  );
}

Map<String, Object?> _inputSchema() => {
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
    };
