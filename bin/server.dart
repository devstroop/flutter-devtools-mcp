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
    stderr.writeln('flutter_devtools_mcp — MCP server for Flutter UI automation');
    stderr.writeln(parser.usage);
    exit(0);
  }

  // -- Setup logging
  Logger.root.level = (parsed['verbose'] as bool) ? Level.ALL : Level.INFO;
  Logger.root.onRecord.listen((record) {
    stderr.writeln('[${record.level.name}] ${record.loggerName}: ${record.message}');
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

  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
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
                'name': 'discover',
                'description': 'Scan for running Flutter debug apps via mDNS. '
                    'Returns a list of detected VM Service URLs and device names. '
                    'Useful before calling connect to see what is available.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'status',
                'description': 'Check connection status. '
                    'Returns whether connected, the VM Service URL if connected, '
                    'and how many running apps are detectable via mDNS.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'connect',
                'description': 'Connect to a Flutter debug app. '
                    'No args = auto-discover first running Flutter app via mDNS. '
                    'Pass a vmServiceUrl to connect explicitly (e.g. from flutter run output). '
                    'Run discover first to see available apps.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'vmServiceUrl': {
                      'type': 'string',
                      'description': 'VM Service WebSocket URL (e.g. ws://127.0.0.1:54321/ws). '
                          'Omit to auto-discover via mDNS.',
                    },
                  },
                },
              },
              {
                'name': 'snapshot',
                'description': 'Requires: connect first. '
                    'Get the current widget tree as LLM-friendly JSON. '
                    'Returns pruned tree with type, label, key, bounds for each node.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'inspect',
                'description': 'Requires: connect first. '
                    'Get detailed properties of a specific widget node.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'nodeId': {'type': 'string', 'description': 'Node ID from snapshot'},
                  },
                  'required': ['nodeId'],
                },
              },
              {
                'name': 'tap',
                'description': 'Requires: connect first. '
                    'Tap a widget. Selector formats: '
                    'semantics:Label, key:value_key, text:Content, index:Type:N',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'selector': {'type': 'string', 'description': 'Widget selector'},
                  },
                  'required': ['selector'],
                },
              },
              {
                'name': 'type_text',
                'description': 'Requires: connect first. '
                    'Focus a text field by selector and enter text.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'selector': {'type': 'string', 'description': 'Text field selector'},
                    'text': {'type': 'string', 'description': 'Text to enter'},
                  },
                  'required': ['selector', 'text'],
                },
              },
              {
                'name': 'scroll',
                'description': 'Requires: connect first. '
                    'Scroll a scrollable widget in a direction.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'selector': {'type': 'string', 'description': 'Scrollable widget selector'},
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
                'description': 'Requires: connect first. '
                    'Capture the current screen as PNG.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'hot_reload',
                'description': 'Requires: connect first. '
                    'Trigger hot reload on the connected Flutter app.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'evaluate',
                'description': 'Requires: connect first. '
                    'Evaluate a Dart expression in the running app.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'expression': {'type': 'string', 'description': 'Dart expression'},
                  },
                  'required': ['expression'],
                },
              },
              {
                'name': 'press_back',
                'description': 'Requires: connect first. '
                    'Press the system back button / pop the top route.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'toggle_dark_mode',
                'description': 'Requires: connect first. '
                    'Toggle dark/light mode. Set enable=true for dark, false for light.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'enable': {'type': 'boolean', 'description': 'true=dark, false=light'},
                  },
                  'required': ['enable'],
                },
              },
              {
                'name': 'toggle_platform',
                'description': 'Requires: connect first. '
                    'Override the target platform (test iOS rendering on Android, etc). '
                    'Values: android, ios, fuchsia, linux, macos, windows.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'platform': {
                      'type': 'string',
                      'enum': ['android', 'ios', 'fuchsia', 'linux', 'macos', 'windows'],
                      'description': 'Target platform to emulate',
                    },
                  },
                  'required': ['platform'],
                },
              },
              {
                'name': 'get_memory',
                'description': 'Requires: connect first. '
                    'Get memory usage of the Flutter app (heap used/capacity, external).',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'dump_semantics',
                'description': 'Requires: connect first. '
                    'Dump the accessibility/semantics tree in traversal order. '
                    'Useful for verifying a11y labels and screen reader output.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'hot_restart',
                'description': 'Requires: connect first. '
                    'Full hot restart — resets all app state while keeping loaded code. '
                    'Unlike hot_reload, this restarts the app from scratch.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'get_errors',
                'description': 'Requires: connect first. '
                    'Get Flutter framework errors from the running app. '
                    'Returns structured error info (red screen errors, layout overflows, etc).',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'toggle_debug_paint',
                'description': 'Requires: connect first. '
                    'Toggle debug paint overlay — shows widget boundaries, padding, '
                    'and alignment guides. Take a screenshot to see the overlay.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'enable': {'type': 'boolean', 'description': 'true to show debug paint, false to hide'},
                  },
                  'required': ['enable'],
                },
              },
              {
                'name': 'toggle_repaint_rainbow',
                'description': 'Requires: connect first. '
                    'Toggle repaint rainbow — rotating colors on repainted regions. '
                    'Helps identify widgets repainting too frequently.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'enable': {'type': 'boolean', 'description': 'true to enable, false to disable'},
                  },
                  'required': ['enable'],
                },
              },
              {
                'name': 'toggle_slow_animations',
                'description': 'Requires: connect first. '
                    'Slow down or restore animation speed. '
                    '1.0 = normal, 2.0 = 2× slower, 5.0 = 5× slower, 10.0 = 10× slower.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'timeDilation': {
                      'type': 'number',
                      'description': 'Time dilation factor (1.0 = normal speed)',
                    },
                  },
                  'required': ['timeDilation'],
                },
              },
              {
                'name': 'toggle_performance_overlay',
                'description': 'Requires: connect first. '
                    'Toggle the performance overlay showing frame timing graphs '
                    '(UI thread and raster thread). Take a screenshot to capture it.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'enable': {'type': 'boolean', 'description': 'true to show overlay, false to hide'},
                  },
                  'required': ['enable'],
                },
              },
              {
                'name': 'get_render_tree',
                'description': 'Requires: connect first. '
                    'Dump the render object tree as text. Shows RenderObject hierarchy '
                    'with layout constraints, sizes, and paint info.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'get_layer_tree',
                'description': 'Requires: connect first. '
                    'Dump the compositing layer tree as text. Shows how render objects '
                    'are composed into GPU layers. Useful for diagnosing compositing overhead.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'get_parent_chain',
                'description': 'Requires: connect first. '
                    'Get the parent chain (ancestor widgets) for a node ID from snapshot. '
                    'Returns the path from the node up to the root widget.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'nodeId': {'type': 'string', 'description': 'Node ID from snapshot'},
                  },
                  'required': ['nodeId'],
                },
              },
              {
                'name': 'track_rebuilds',
                'description': 'Requires: connect first. '
                    'Toggle widget rebuild tracking. When enabled, widgets show '
                    'rebuild counts in the inspector overlay.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'enable': {'type': 'boolean', 'description': 'true to start tracking, false to stop'},
                  },
                  'required': ['enable'],
                },
              },
              {
                'name': 'track_repaints',
                'description': 'Requires: connect first. '
                    'Toggle repaint tracking. When enabled, highlights render objects '
                    'that are repainting.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'enable': {'type': 'boolean', 'description': 'true to start tracking, false to stop'},
                  },
                  'required': ['enable'],
                },
              },
              {
                'name': 'get_logs',
                'description': 'Requires: connect first. '
                    'Capture recent app output — stdout, stderr, and dart:developer log() '
                    'messages. Returns logs collected within a brief window.',
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
                {'type': 'text', 'text': 'Error: missing required "name" parameter'},
              ],
            };
            break;
          }
          final toolArgs = (params['arguments'] as Map<String, Object?>?) ?? {};

          // discover tool — scan for running Flutter apps via mDNS
          if (toolName == 'discover') {
            final services = await discoverFlutterVmServices();
            final apps = services.map((s) => s.wsUrl).toList();
            String text;
            if (apps.isEmpty) {
              text = '{"status":"ok","apps":[],"message":"No running Flutter debug apps found. '
                  'Start one with: cd <your_flutter_project> && flutter run --debug"}';
            } else {
              text = '{"status":"ok","apps":${json.encode(apps)},"message":"Found ${apps.length} running Flutter app(s). '
                  'Use connect with one of these URLs or call connect with no args to auto-connect."}';
            }
            result = {'content': [{'type': 'text', 'text': text}]};
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
            result = {'content': [{'type': 'text', 'text': json.encode(map)}]};
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
                    'text': '{"status":"error","error":"Failed to connect to Flutter app."'
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
                    'text': '{"status":"connected","url":"${connection.vmServiceUrl}"}',
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
                {'type': 'text', 'text': 'Error: Not connected to a Flutter app. $hint'},
              ],
            };
            break;
          }

          result = await _handleToolCall(
            connection, trace, toolName, toolArgs,
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

Future<FlutterConnection?> _connectToFlutter(Logger log, String? configuredVmUrl) async {
  String? vmUrl = configuredVmUrl;

  if (vmUrl == null) {
    // Auto-discover via mDNS — Flutter apps broadcast _dartobservatory._tcp
    stderr.writeln('No VM Service URL provided. Scanning for Flutter apps via mDNS...');
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
    if (msg.contains('WebSocketException') || msg.contains('Connection refused')) {
      stderr.writeln('Could not open WebSocket to $vmUrl');
      stderr.writeln('Ensure the Flutter app is running in debug mode and the URL is correct.');
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
      'inspect' => await inspectTool(connection, _requireArg<String>(args, 'nodeId')),
      'tap' => await tapTool(connection, _requireArg<String>(args, 'selector'), trace),
      'type_text' => await typeTextTool(
          connection, _requireArg<String>(args, 'selector'),
          _requireArg<String>(args, 'text'), trace),
      'scroll' => await scrollTool(
          connection, _requireArg<String>(args, 'selector'),
          _requireArg<String>(args, 'direction'), trace,
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
