import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../connection_factory.dart';
import '../mcp_transport.dart';
import 'launch_state.dart';

/// Regex to extract the VM Service URL from flutter run stdout.
final _vmServiceUrlPattern = RegExp(
  r'(ws|http)s?://127\.0\.0\.1:\d+/([a-zA-Z0-9]+/)?ws?',
);

/// MCP tool impl: launch
///
/// Launch a Flutter app in debug mode from a project directory.
ToolDef createLaunchTool(ConnectionFactory factory) {
  return ToolDef(
    name: 'launch',
    description: 'Launch a Flutter app in debug mode from a project directory. '
        'Starts flutter run as a subprocess, waits for the VM Service URL, '
        'then auto-connects. Use stop_app to kill the launched process.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'projectPath': {
          'type': 'string',
          'description':
              'Absolute path to the Flutter project directory (containing pubspec.yaml)',
        },
        'deviceId': {
          'type': 'string',
          'description':
              'Target device ID (e.g. macos, ios, android, chrome). Defaults to macos.',
        },
        'target': {
          'type': 'string',
          'description':
              'Target file to run (e.g. lib/main.dart). Defaults to lib/main.dart.',
        },
        'launchTimeout': {
          'type': 'number',
          'description':
              'Maximum seconds to wait for the app to start. Default: 120.',
        },
      },
      'required': ['projectPath'],
    },
    handler: (args) async {
      final projectPath = args['projectPath'] as String;
      final deviceId = args['deviceId'] as String? ?? 'macos';
      final target = args['target'] as String? ?? 'lib/main.dart';
      final launchTimeoutSec = (args['launchTimeout'] as num?)?.toInt() ?? 120;

      // Kill any previously running launch
      if (launchState.process != null) {
        killLaunchedProcess();
      }
      launchState.log.clear();

      // Validate project directory
      final projectDir = Directory(projectPath);
      if (!projectDir.existsSync()) {
        return {
          'isError': true,
          'content': [
            {
              'type': 'text',
              'text': 'Error: Project directory not found: $projectPath'
            },
          ],
        };
      }
      final pubspec = File('$projectPath/pubspec.yaml');
      if (!pubspec.existsSync()) {
        return {
          'isError': true,
          'content': [
            {
              'type': 'text',
              'text':
                  'Error: No pubspec.yaml found in $projectPath. Is this a Flutter project?',
            },
          ],
        };
      }

      launchState.projectPath = projectPath;
      launchState.log
          .add('Launching: flutter run -d $deviceId --debug $target');

      try {
        final process = await Process.start(
          'flutter',
          ['run', '-d', deviceId, '--debug', target],
          workingDirectory: projectPath,
          runInShell: true,
        );

        launchState.process = process;
        launchState.alive = true;
        process.exitCode.then((_) => launchState.alive = false);

        // Collect stdout
        final stdoutLines = <String>[];
        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          stdoutLines.add(line);
          if (stdoutLines.length > 200) stdoutLines.removeAt(0);
        });
        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          launchState.log.add('[stderr] $line');
        });

        // Wait for VM Service URL with timeout
        final deadline =
            DateTime.now().add(Duration(seconds: launchTimeoutSec));
        String? vmUrl;

        while (DateTime.now().isBefore(deadline)) {
          if (!launchState.alive) {
            final code = await process.exitCode;
            launchState.log.add('Process exited with code $code');
            break;
          }
          for (final line in stdoutLines) {
            final match = _vmServiceUrlPattern.firstMatch(line);
            if (match != null) {
              vmUrl = match.group(0)!;
              launchState.log.add('VM Service URL found: $vmUrl');
              break;
            }
          }
          if (vmUrl != null) break;
          await Future.delayed(const Duration(milliseconds: 500));
        }

        if (vmUrl == null) {
          final recent =
              stdoutLines.where((l) => l.trim().isNotEmpty).join('\n');
          return {
            'isError': true,
            'content': [
              {
                'type': 'text',
                'text':
                    '{"status":"error","error":"Timed out waiting for VM Service URL after ${launchTimeoutSec}s.","output":${json.encode(recent.length > 500 ? recent.substring(0, 500) : recent)}}',
              },
            ],
          };
        }

        // Auto-connect via factory
        try {
          await factory.getConnection(vmUrl);
          return {
            'content': [
              {
                'type': 'text',
                'text':
                    '{"status":"launched","url":"$vmUrl","pid":${process.pid},"connected":true}',
              },
            ],
          };
        } catch (e) {
          return {
            'isError': true,
            'content': [
              {
                'type': 'text',
                'text':
                    '{"status":"launched","url":"$vmUrl","pid":${process.pid},"connected":false,"error":"$e"}',
              },
            ],
          };
        }
      } catch (e) {
        launchState.process = null;
        return {
          'isError': true,
          'content': [
            {'type': 'text', 'text': 'Error launching Flutter app: $e'},
          ],
        };
      }
    },
  );
}
