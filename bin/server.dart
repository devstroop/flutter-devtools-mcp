import 'dart:io';
import 'dart:convert';
import 'package:args/args.dart';
import 'package:logging/logging.dart';

import 'package:flutter_devtools_mcp/src/connection.dart';
import 'package:flutter_devtools_mcp/src/discovery.dart';
import 'package:flutter_devtools_mcp/src/trace.dart';
import 'package:flutter_devtools_mcp/src/tools/snapshot.dart';
import 'package:flutter_devtools_mcp/src/tools/inspect.dart';
import 'package:flutter_devtools_mcp/src/tools/tap.dart';
import 'package:flutter_devtools_mcp/src/tools/type_text.dart';
import 'package:flutter_devtools_mcp/src/tools/scroll.dart';
import 'package:flutter_devtools_mcp/src/tools/screenshot.dart';
import 'package:flutter_devtools_mcp/src/tools/hot_reload.dart';
import 'package:flutter_devtools_mcp/src/tools/evaluate.dart';
import 'package:flutter_devtools_mcp/src/tools/press_back.dart';
import 'package:flutter_devtools_mcp/src/tools/toggle_dark_mode.dart';
import 'package:flutter_devtools_mcp/src/tools/toggle_platform.dart';
import 'package:flutter_devtools_mcp/src/tools/get_memory.dart';
import 'package:flutter_devtools_mcp/src/tools/dump_semantics.dart';
import 'package:flutter_devtools_mcp/src/tools/hot_restart.dart';
import 'package:flutter_devtools_mcp/src/tools/get_errors.dart';
import 'package:flutter_devtools_mcp/src/tools/toggle_debug_paint.dart';
import 'package:flutter_devtools_mcp/src/tools/toggle_repaint_rainbow.dart';
import 'package:flutter_devtools_mcp/src/tools/toggle_slow_animations.dart';
import 'package:flutter_devtools_mcp/src/tools/toggle_performance_overlay.dart';
import 'package:flutter_devtools_mcp/src/tools/get_render_tree.dart';
import 'package:flutter_devtools_mcp/src/tools/get_layer_tree.dart';
import 'package:flutter_devtools_mcp/src/tools/get_parent_chain.dart';
import 'package:flutter_devtools_mcp/src/tools/track_rebuilds.dart';
import 'package:flutter_devtools_mcp/src/tools/track_repaints.dart';
import 'package:flutter_devtools_mcp/src/tools/get_logs.dart';

// -- Launched app process tracking (module-level for access by helpers)
Process? _launchedProcess;
String? _launchedProjectPath;
final _launchLog = <String>[];
bool _launchedProcessAlive = false;

/// MCP server entry point.
///
/// Communicates via stdio JSON-RPC (MCP transport).
/// Connects to a Flutter app's VM Service WebSocket.
void main(List<String> args) async {
  // -- Parse args
  final parser = ArgParser()
    ..addOption('vm-service-url', abbr: 'u', help: 'VM Service WebSocket URL')
    ..addFlag('verbose', abbr: 'v', defaultsTo: false)
    ..addFlag('help', abbr: 'h', negatable: false);

  final parsed = parser.parse(args);
  if (parsed['help'] as bool) {
    stderr
        .writeln('flutter_devtools_mcp — MCP server for Flutter UI automation');
    stderr.writeln(parser.usage);
    exit(0);
  }

  // -- Setup logging
  Logger.root.level = (parsed['verbose'] as bool) ? Level.ALL : Level.INFO;
  Logger.root.onRecord.listen((record) {
    stderr.writeln(
        '[${record.level.name}] ${record.loggerName}: ${record.message}');
  });

  final log = Logger('Server');

  // -- Resolve optional VM Service URL (may be discovered lazily on first tool call)
  final configuredVmUrl = (parsed['vm-service-url'] as String?) ??
      Platform.environment['FLUTTER_VM_SERVICE_URL'];

  FlutterConnection? connection;
  final trace = TraceLog();

  // -- MCP stdio transport
  // Read JSON-RPC requests from stdin, write responses to stdout.
  log.info('MCP server ready. Listening on stdio.');

  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;

    try {
      final request = json.decode(line) as Map<String, Object?>;
      final method = request['method'] as String?;
      final id = request['id'];
      final params = (request['params'] as Map<String, Object?>?) ?? {};

      Map<String, Object?>? result;

      switch (method) {
        // -- MCP lifecycle
        case 'initialize':
          result = {
            'protocolVersion': '2024-11-05',
            'capabilities': {'tools': {}},
            'serverInfo': {
              'name': 'flutter_devtools_mcp',
              'version': '0.1.0',
              'usage': 'When you see a Dart VM Service URL in terminal output '
                  '(e.g. http://127.0.0.1:PORT/TOKEN=/), '
                  'call the connect tool with that URL as vmServiceUrl to attach.',
            },
          };

        // Notification — no response required
        case 'notifications/initialized':
          log.info('Client initialized');
          continue;

        // Graceful shutdown
        case 'shutdown':
          log.info('Shutdown requested');
          result = {};

        case 'exit':
          log.info('Exit requested');
          _killLaunchedProcess();
          await connection?.disconnect();
          exit(0);

        case 'ping':
          result = {};

        case 'resources/list':
          result = {'resources': []};

        case 'prompts/list':
          result = {'prompts': []};

        case 'tools/list':
          result = {
            'tools': [
              {
                'name': 'launch',
                'description':
                    'Launch a Flutter app in debug mode from a project directory. '
                        'Starts flutter run as a subprocess, waits for the VM Service URL, '
                        'then auto-connects. Returns the URL once the app is ready. '
                        'Use stop_app to kill the launched process.',
                'inputSchema': {
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
              },
              {
                'name': 'launch_status',
                'description':
                    'Check the status of the most recently launched app process. '
                        'Returns whether the process is alive, the VM Service URL if resolved, '
                        'and recent stdout/stderr output.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'stop_app',
                'description': 'Stop a running app launched via the launch tool. '
                    'Kills the flutter run process and disconnects from the VM Service.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'discover',
                'description': 'Scan for running Flutter debug apps via mDNS. '
                    'Returns ws://127.0.0.1:PORT/TOKEN=/ws URLs. '
                    'Pass any returned URL to connect to attach to that app.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'status',
                'description': 'Check connection status. '
                    'Returns whether connected, the attached app URL, '
                    'and how many running apps are detectable via mDNS. '
                    'Always call this first after connect to verify before using other tools.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'connect',
                'description': 'ATTACH to a running Flutter debug app by passing its VM Service URL. '
                    'When you run flutter run and see "A Dart VM Service is available at: '
                    'http://127.0.0.1:PORT/TOKEN=/" in the terminal, copy that EXACT http:// URL '
                    '(with the token) and pass it as vmServiceUrl. The server auto-normalizes '
                    'http:// to ws:// and appends /ws. No args = auto-discover via mDNS.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'vmServiceUrl': {
                      'type': 'string',
                      'description':
                          'The full VM Service URL from flutter run output, '
                              'e.g. http://127.0.0.1:54321/abc123=/. '
                              'Both http:// and ws:// formats work. '
                              'Omit to auto-discover via mDNS.',
                    },
                  },
                },
              },
              {
                'name': 'snapshot',
                'description':
                    'REQUIRES: connect first (use the connect tool with the VM Service URL from flutter run output). '
                        'Get the current widget tree as LLM-friendly JSON. '
                        'Returns pruned tree with type, label, key, bounds for each node.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'inspect',
                'description': 'REQUIRES: connect first. '
                    'Get detailed properties of a specific widget node.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'nodeId': {
                      'type': 'string',
                      'description': 'Node ID from snapshot'
                    },
                  },
                  'required': ['nodeId'],
                },
              },
              {
                'name': 'tap',
                'description':
                    'REQUIRES: connect first. Tap a widget by selector (semantics:, key:, text:, index:).',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'selector': {
                      'type': 'string',
                      'description': 'Widget selector'
                    },
                  },
                  'required': ['selector'],
                },
              },
              {
                'name': 'type_text',
                'description':
                    'REQUIRES: connect first. Focus a text field by selector and enter text.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'selector': {
                      'type': 'string',
                      'description': 'Text field selector'
                    },
                    'text': {'type': 'string', 'description': 'Text to enter'},
                  },
                  'required': ['selector', 'text'],
                },
              },
              {
                'name': 'scroll',
                'description':
                    'REQUIRES: connect first. Scroll a scrollable widget.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'selector': {
                      'type': 'string',
                      'description': 'Scrollable widget selector'
                    },
                    'direction': {
                      'type': 'string',
                      'enum': ['up', 'down', 'left', 'right'],
                      'description': 'Scroll direction',
                    },
                    'amount': {
                      'type': 'number',
                      'description': 'Scroll amount in pixels (default: 300)',
                    },
                  },
                  'required': ['selector', 'direction'],
                },
              },
              {
                'name': 'screenshot',
                'description':
                    'REQUIRES: connect first. Capture the current screen as PNG.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'hot_reload',
                'description': 'REQUIRES: connect first. Trigger hot reload.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'evaluate',
                'description':
                    'REQUIRES: connect first. Evaluate a Dart expression.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'expression': {
                      'type': 'string',
                      'description': 'Dart expression'
                    },
                  },
                  'required': ['expression'],
                },
              },
              {
                'name': 'press_back',
                'description':
                    'REQUIRES: connect first. Press back / pop route.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'toggle_dark_mode',
                'description':
                    'REQUIRES: connect first. Toggle dark/light mode.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'enable': {
                      'type': 'boolean',
                      'description': 'true=dark, false=light'
                    },
                  },
                  'required': ['enable'],
                },
              },
              {
                'name': 'toggle_platform',
                'description':
                    'REQUIRES: connect first. Override target platform.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'platform': {
                      'type': 'string',
                      'enum': [
                        'android',
                        'ios',
                        'fuchsia',
                        'linux',
                        'macos',
                        'windows'
                      ],
                      'description': 'Target platform to emulate',
                    },
                  },
                  'required': ['platform'],
                },
              },
              {
                'name': 'get_memory',
                'description': 'REQUIRES: connect first. Get memory usage.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'dump_semantics',
                'description': 'REQUIRES: connect first. Dump semantics tree.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'hot_restart',
                'description':
                    'REQUIRES: connect first. Hot restart (resets state).',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'get_errors',
                'description':
                    'REQUIRES: connect first. Get Flutter framework errors.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'toggle_debug_paint',
                'description':
                    'REQUIRES: connect first. Toggle debug paint overlay.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'enable': {
                      'type': 'boolean',
                      'description': 'true to show debug paint, false to hide'
                    },
                  },
                  'required': ['enable'],
                },
              },
              {
                'name': 'toggle_repaint_rainbow',
                'description':
                    'REQUIRES: connect first. Toggle repaint rainbow.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'enable': {
                      'type': 'boolean',
                      'description': 'true to enable, false to disable'
                    },
                  },
                  'required': ['enable'],
                },
              },
              {
                'name': 'toggle_slow_animations',
                'description':
                    'REQUIRES: connect first. Slow down or restore animations.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'timeDilation': {
                      'type': 'number',
                      'description':
                          'Time dilation factor (1.0 = normal speed)',
                    },
                  },
                  'required': ['timeDilation'],
                },
              },
              {
                'name': 'toggle_performance_overlay',
                'description':
                    'REQUIRES: connect first. Toggle performance overlay.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'enable': {
                      'type': 'boolean',
                      'description': 'true to show overlay, false to hide'
                    },
                  },
                  'required': ['enable'],
                },
              },
              {
                'name': 'get_render_tree',
                'description':
                    'REQUIRES: connect first. Dump render object tree.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'get_layer_tree',
                'description':
                    'REQUIRES: connect first. Dump compositing layer tree.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'get_parent_chain',
                'description':
                    'REQUIRES: connect first. Get parent chain for a node.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'nodeId': {
                      'type': 'string',
                      'description': 'Node ID from snapshot'
                    },
                  },
                  'required': ['nodeId'],
                },
              },
              {
                'name': 'track_rebuilds',
                'description':
                    'REQUIRES: connect first. Track widget rebuilds.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'enable': {
                      'type': 'boolean',
                      'description': 'true to start tracking, false to stop'
                    },
                  },
                  'required': ['enable'],
                },
              },
              {
                'name': 'track_repaints',
                'description':
                    'REQUIRES: connect first. Track widget repaints.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'enable': {
                      'type': 'boolean',
                      'description': 'true to start tracking, false to stop'
                    },
                  },
                  'required': ['enable'],
                },
              },
              {
                'name': 'get_logs',
                'description':
                    'REQUIRES: connect first. Capture recent app logs.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
            ],
          };

        case 'tools/call':
          final toolName = params['name'] as String?;
          if (toolName == null) {
            result = {
              'isError': true,
              'content': [
                {
                  'type': 'text',
                  'text': 'Error: missing required "name" parameter'
                },
              ],
            };
            break;
          }
          final toolArgs = (params['arguments'] as Map<String, Object?>?) ?? {};

          // launch tool — start flutter run and wait for VM Service URL
          if (toolName == 'launch') {
            final projectPath = _requireArg<String>(toolArgs, 'projectPath');
            final deviceId = toolArgs['deviceId'] as String? ?? 'macos';
            final target = toolArgs['target'] as String? ?? 'lib/main.dart';
            final launchTimeoutSec =
                (toolArgs['launchTimeout'] as num?)?.toInt() ?? 120;

            // Kill any previously running launch
            if (_launchedProcess != null) {
              _killLaunchedProcess();
            }
            _launchLog.clear();

            // Validate project directory
            final projectDir = Directory(projectPath);
            if (!projectDir.existsSync()) {
              result = {
                'isError': true,
                'content': [
                  {
                    'type': 'text',
                    'text': 'Error: Project directory not found: $projectPath',
                  },
                ],
              };
              break;
            }
            final pubspec = File('$projectPath/pubspec.yaml');
            if (!pubspec.existsSync()) {
              result = {
                'isError': true,
                'content': [
                  {
                    'type': 'text',
                    'text':
                        'Error: No pubspec.yaml found in $projectPath. Is this a Flutter project?',
                  },
                ],
              };
              break;
            }

            _launchedProjectPath = projectPath;
            _launchLog
                .add('Launching: flutter run -d $deviceId --debug $target');

            try {
              final process = await Process.start(
                'flutter',
                [
                  'run',
                  '-d',
                  deviceId,
                  '--debug',
                  target,
                ],
                workingDirectory: projectPath,
                runInShell: true,
              );

              _launchedProcess = process;
              _launchedProcessAlive = true;
              process.exitCode.then((_) => _launchedProcessAlive = false);

              // Collect stdout/stderr in background
              final stdoutLines = <String>[];
              final stderrLines = <String>[];
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
                stderrLines.add(line);
                if (stderrLines.length > 200) stderrLines.removeAt(0);
              });

              // Wait for VM Service URL with timeout
              final deadline =
                  DateTime.now().add(Duration(seconds: launchTimeoutSec));
              String? vmUrl;

              while (DateTime.now().isBefore(deadline)) {
                // Check if process exited
                if (!_launchedProcessAlive) {
                  final code = await process.exitCode;
                  _launchLog.add('Process exited with code $code');
                  break;
                }

                // Scan stdout for VM Service URL
                for (final line in stdoutLines) {
                  final match = _vmServiceUrlPattern.firstMatch(line);
                  if (match != null) {
                    vmUrl = match.group(0)!;
                    _launchLog.add('VM Service URL found: $vmUrl');
                    break;
                  }
                }
                if (vmUrl != null) break;

                await Future.delayed(const Duration(milliseconds: 500));
              }

              // Capture recent output for the response
              final recentStdout = stdoutLines
                  .join('\n')
                  .split('\n')
                  .where((l) => l.trim().isNotEmpty)
                  .join('\n');
              _launchLog.addAll(
                  stdoutLines.where((l) => l.trim().isNotEmpty).take(10));

              if (vmUrl == null) {
                result = {
                  'isError': true,
                  'content': [
                    {
                      'type': 'text',
                      'text':
                          '{"status":"error","error":"Timed out waiting for VM Service URL after ${launchTimeoutSec}s.","output":${json.encode(recentStdout.split('\n').where((l) => l.trim().isNotEmpty).take(20).join('\n'))}}',
                    },
                  ],
                };
                break;
              }

              // Auto-connect to the launched app
              await connection?.disconnect();
              connection = null;
              final newConn = await _connectToFlutter(log, vmUrl);
              if (newConn == null) {
                result = {
                  'isError': true,
                  'content': [
                    {
                      'type': 'text',
                      'text':
                          '{"status":"error","error":"App launched but failed to connect to VM Service at $vmUrl"}',
                    },
                  ],
                };
              } else {
                connection = newConn;
                result = {
                  'content': [
                    {
                      'type': 'text',
                      'text':
                          '{"status":"launched","url":"$vmUrl","pid":${process.pid},"connected":true}',
                    },
                  ],
                };
              }
            } catch (e) {
              _launchedProcess = null;
              result = {
                'isError': true,
                'content': [
                  {
                    'type': 'text',
                    'text': 'Error launching Flutter app: $e',
                  },
                ],
              };
            }
            break;
          }

          // launch_status tool — check on the launched process
          if (toolName == 'launch_status') {
            final alive = _launchedProcess != null && _launchedProcessAlive;
            final map = <String, Object?>{
              'alive': alive,
              'projectPath': _launchedProjectPath,
              'logLines': _launchLog.length,
              'recentLog': _launchLog.join('\n'),
            };
            if (_launchedProcess != null && alive) {
              map['pid'] = _launchedProcess!.pid;
            }
            result = {
              'content': [
                {'type': 'text', 'text': json.encode(map)}
              ],
            };
            break;
          }

          // stop_app tool — kill the launched process
          if (toolName == 'stop_app') {
            if (_launchedProcess == null) {
              result = {
                'isError': true,
                'content': [
                  {
                    'type': 'text',
                    'text':
                        'Error: No app has been launched via the launch tool.',
                  },
                ],
              };
              break;
            }
            await connection?.disconnect();
            connection = null;
            final stoppedPath = _launchedProjectPath;
            _killLaunchedProcess();
            _launchedProjectPath = null;
            _launchLog.add('App stopped by stop_app tool');
            result = {
              'content': [
                {
                  'type': 'text',
                  'text': '{"status":"stopped","projectPath":"$stoppedPath"}',
                },
              ],
            };
            break;
          }

          // discover tool — scan for running Flutter apps via mDNS
          if (toolName == 'discover') {
            final services = await discoverFlutterVmServices();
            final apps = services.map((s) => s.wsUrl).toList();
            String text;
            if (apps.isEmpty) {
              text =
                  '{"status":"ok","apps":[],"message":"No running Flutter debug apps found. '
                  'Start one with: cd <your_flutter_project> && flutter run --debug"}';
            } else {
              text =
                  '{"status":"ok","apps":${json.encode(apps)},"message":"Found ${apps.length} running Flutter app(s). '
                  'Use connect with one of these URLs or call connect with no args to auto-connect."}';
            }
            result = {
              'content': [
                {'type': 'text', 'text': text}
              ]
            };
            break;
          }

          // status tool — check whether connected and what's available
          if (toolName == 'status') {
            final isConnected = connection != null;
            final services = await discoverFlutterVmServices();
            final apps = services.map((s) => s.wsUrl).toList();
            final map = <String, Object?>{
              'connected': isConnected,
              'appCount': apps.length,
              'apps': apps,
            };
            if (isConnected) {
              map['url'] = connection.vmServiceUrl;
              map['isolateId'] = connection.isolateId;
            }
            result = {
              'content': [
                {'type': 'text', 'text': json.encode(map)}
              ]
            };
            break;
          }

          // connect tool manages the connection lifecycle explicitly
          if (toolName == 'connect') {
            await connection?.disconnect();
            connection = null;
            final vmUrl = toolArgs['vmServiceUrl'] as String?;
            final newConn = await _connectToFlutter(log, vmUrl);
            if (newConn == null) {
              // Include discoverable apps in the error for guidance
              final services = await discoverFlutterVmServices();
              String extra = '';
              if (services.isEmpty) {
                extra = ' No running Flutter debug apps detected. '
                    'Make sure a Flutter app is running in debug mode: '
                    'cd <your_flutter_project> && flutter run --debug';
              } else {
                extra = ' Detected running app(s): '
                    '${services.map((s) => s.wsUrl).join(', ')}. '
                    'Pass the desired URL to connect, or omit vmServiceUrl to auto-connect.';
              }
              result = {
                'isError': true,
                'content': [
                  {
                    'type': 'text',
                    'text':
                        '{"status":"error","error":"Failed to connect to Flutter app."'
                            '"hint":"$extra"}',
                  },
                ],
              };
            } else {
              connection = newConn;
              result = {
                'content': [
                  {
                    'type': 'text',
                    'text':
                        '{"status":"connected","url":"${connection.vmServiceUrl}"}',
                  },
                ],
              };
            }
            break;
          }

          // All other tools need a connection — try auto-connect via mDNS
          connection ??= await _connectToFlutter(log, configuredVmUrl);
          if (connection == null) {
            final services = await discoverFlutterVmServices();
            String hint;
            if (services.isEmpty) {
              hint = 'No running Flutter debug apps found via mDNS. '
                  'Start one with: cd <your_flutter_project> && flutter run --debug. '
                  'Then retry this tool or call connect first.';
            } else {
              hint = 'Found ${services.length} running app(s): '
                  '${services.map((s) => s.wsUrl).join(', ')}. '
                  'Call connect with one of these URLs first.';
            }
            result = {
              'isError': true,
              'content': [
                {
                  'type': 'text',
                  'text': 'Error: Not connected to a Flutter app. $hint'
                },
              ],
            };
            break;
          }

          result = await _handleToolCall(
            connection,
            trace,
            toolName,
            toolArgs,
          );

        default:
          if (id != null) {
            // Unknown method with an id = request → send JSON-RPC error
            _respondError(id, -32601, 'Method not found: $method');
          }
          // Unknown method without id = notification → ignore
          continue;
      }

      if (id != null) {
        _respond(id, result);
      }
    } catch (e, st) {
      log.severe('Error processing request: $e', e, st);
      // Try to extract the request id to send an error response
      try {
        final request = json.decode(line) as Map<String, Object?>;
        final id = request['id'];
        if (id != null) {
          _respondError(id, -32603, 'Internal error: $e');
        }
      } catch (_) {
        // Malformed JSON — nothing we can respond to
      }
    }
  }

  await connection?.disconnect();
}

Future<FlutterConnection?> _connectToFlutter(
    Logger log, String? configuredVmUrl) async {
  String? vmUrl = configuredVmUrl;

  if (vmUrl == null) {
    // Auto-discover via mDNS — Flutter apps broadcast _dartobservatory._tcp
    stderr.writeln(
        'No VM Service URL provided. Scanning for Flutter apps via mDNS...');
    final services = await discoverFlutterVmServices();

    if (services.isEmpty) {
      stderr.writeln('No running Flutter debug apps found.');
      return null;
    }

    if (services.length > 1) {
      stderr.writeln('Multiple Flutter apps found — connecting to the first:');
      for (final s in services) {
        stderr.writeln('  ${s.wsUrl}');
      }
    }

    vmUrl = services.first.wsUrl;
    log.info('Auto-discovered VM Service: $vmUrl');
  }

  final connection = FlutterConnection(vmServiceUrl: vmUrl);
  try {
    await connection.connect();
    log.info('Connected to Flutter app');
    return connection;
  } on ArgumentError catch (e) {
    stderr.writeln('Invalid VM Service URL: $e');
    stderr.writeln('URL must be a localhost WebSocket (ws://127.0.0.1:...)');
    return null;
  } on SocketException catch (e) {
    stderr.writeln('Connection refused at $vmUrl');
    stderr.writeln('Is your Flutter app running? Error: ${e.message}');
    return null;
  } catch (e) {
    final msg = e.toString();
    if (msg.contains('WebSocketException') ||
        msg.contains('Connection refused')) {
      stderr.writeln('Could not open WebSocket to $vmUrl');
      stderr.writeln(
          'Ensure the Flutter app is running in debug mode and the URL is correct.');
    } else {
      stderr.writeln('Failed to connect to VM Service at $vmUrl: $e');
    }
    return null;
  }
}

Future<Map<String, Object?>> _handleToolCall(
  FlutterConnection connection,
  TraceLog trace,
  String tool,
  Map<String, Object?> args,
) async {
  try {
    final content = switch (tool) {
      'snapshot' => await snapshotTool(connection),
      'inspect' =>
        await inspectTool(connection, _requireArg<String>(args, 'nodeId')),
      'tap' =>
        await tapTool(connection, _requireArg<String>(args, 'selector'), trace),
      'type_text' => await typeTextTool(
          connection,
          _requireArg<String>(args, 'selector'),
          _requireArg<String>(args, 'text'),
          trace),
      'scroll' => await scrollTool(
          connection,
          _requireArg<String>(args, 'selector'),
          _requireArg<String>(args, 'direction'),
          trace,
          amount: (args['amount'] as num?)?.toDouble() ?? 300.0),
      'screenshot' => await screenshotTool(connection, trace),
      'hot_reload' => await hotReloadTool(connection, trace),
      'evaluate' => await evaluateTool(
          connection, _requireArg<String>(args, 'expression'), trace),
      'press_back' => await pressBackTool(connection, trace),
      'toggle_dark_mode' => await toggleDarkModeTool(
          connection, _requireArg<bool>(args, 'enable'), trace),
      'toggle_platform' => await togglePlatformTool(
          connection, _requireArg<String>(args, 'platform'), trace),
      'get_memory' => await getMemoryTool(connection, trace),
      'dump_semantics' => await dumpSemanticsTool(connection, trace),
      'hot_restart' => await hotRestartTool(connection, trace),
      'get_errors' => await getErrorsTool(connection, trace),
      'toggle_debug_paint' => await toggleDebugPaintTool(
          connection, _requireArg<bool>(args, 'enable'), trace),
      'toggle_repaint_rainbow' => await toggleRepaintRainbowTool(
          connection, _requireArg<bool>(args, 'enable'), trace),
      'toggle_slow_animations' => await toggleSlowAnimationsTool(
          connection, (args['timeDilation'] as num).toDouble(), trace),
      'toggle_performance_overlay' => await togglePerformanceOverlayTool(
          connection, _requireArg<bool>(args, 'enable'), trace),
      'get_render_tree' => await getRenderTreeTool(connection, trace),
      'get_layer_tree' => await getLayerTreeTool(connection, trace),
      'get_parent_chain' => await getParentChainTool(
          connection, _requireArg<String>(args, 'nodeId'), trace),
      'track_rebuilds' => await trackRebuildsTool(
          connection, _requireArg<bool>(args, 'enable'), trace),
      'track_repaints' => await trackRepaintsTool(
          connection, _requireArg<bool>(args, 'enable'), trace),
      'get_logs' => await getLogsTool(connection, trace),
      _ => {'error': 'Unknown tool: $tool'},
    };

    // Return screenshot with MCP image content type when possible
    if (tool == 'screenshot') {
      final screenshotResult = content;
      final data = screenshotResult['data'] as String?;
      if (data != null && screenshotResult['status'] == 'success') {
        return {
          'content': [
            {'type': 'image', 'data': data, 'mimeType': 'image/png'},
          ],
        };
      }
    }

    return {
      'content': [
        {'type': 'text', 'text': json.encode(content)},
      ],
    };
  } catch (e) {
    return {
      'isError': true,
      'content': [
        {'type': 'text', 'text': 'Error: $e'},
      ],
    };
  }
}

void _respond(Object id, Map<String, Object?>? result) {
  final response = json.encode({
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  });
  stdout.writeln(response);
}

void _respondError(Object id, int code, String message) {
  final response = json.encode({
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  });
  stdout.writeln(response);
}

/// Extract a required argument from tool args, with a clear error message.
T _requireArg<T extends Object>(Map<String, Object?> args, String name) {
  final value = args[name];
  if (value == null) {
    throw ArgumentError('Missing required parameter: "$name"');
  }
  if (value is! T) {
    throw ArgumentError(
      'Parameter "$name" must be $T, got ${value.runtimeType}',
    );
  }
  return value;
}

/// Regex to extract the VM Service WebSocket URL from flutter run output.
///
/// Matches patterns like:
///   ws://127.0.0.1:54321/abc123=/ws
///   http://127.0.0.1:54321/abc123/
final _vmServiceUrlPattern = RegExp(
  r'(ws|http)s?://127\.0\.0\.1:\d+/([a-zA-Z0-9]+/)?ws?',
);

/// Kill the currently tracked launched Flutter process.
void _killLaunchedProcess() {
  final proc = _launchedProcess;
  if (proc == null) return;
  _launchedProcessAlive = false;
  try {
    proc.kill(ProcessSignal.sigterm);
    // Give it a moment, then force kill
    Future.delayed(const Duration(seconds: 2), () {
      try {
        proc.kill(ProcessSignal.sigkill);
      } catch (_) {}
    });
  } catch (_) {}
  _launchedProcess = null;
}
