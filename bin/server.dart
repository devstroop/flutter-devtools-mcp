import 'dart:io';
import 'dart:convert';
import 'package:args/args.dart';
import 'package:logging/logging.dart';

import 'package:flutter_devtools_mcp/src/connection.dart';
import 'package:flutter_devtools_mcp/src/trace.dart';
import 'package:flutter_devtools_mcp/src/tools/snapshot.dart';
import 'package:flutter_devtools_mcp/src/tools/inspect.dart';
import 'package:flutter_devtools_mcp/src/tools/tap.dart';
import 'package:flutter_devtools_mcp/src/tools/type_text.dart';
import 'package:flutter_devtools_mcp/src/tools/scroll.dart';
import 'package:flutter_devtools_mcp/src/tools/screenshot.dart';
import 'package:flutter_devtools_mcp/src/tools/hot_reload.dart';
import 'package:flutter_devtools_mcp/src/tools/evaluate.dart';

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

  // -- Resolve VM Service URL
  final vmUrl = (parsed['vm-service-url'] as String?) ??
      Platform.environment['FLUTTER_VM_SERVICE_URL'];

  if (vmUrl == null) {
    stderr.writeln('Error: Provide VM Service URL via --vm-service-url or '
        'FLUTTER_VM_SERVICE_URL env var.');
    stderr.writeln('Run your Flutter app with: flutter run --debug');
    stderr.writeln('Then copy the VM Service URL from the output.');
    exit(1);
  }

  // -- Connect
  final connection = FlutterConnection(vmServiceUrl: vmUrl);
  final trace = TraceLog();

  try {
    await connection.connect();
    log.info('Connected to Flutter app');
  } catch (e) {
    stderr.writeln('Failed to connect to VM Service at $vmUrl: $e');
    exit(1);
  }

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
          await connection.disconnect();
          exit(0);

        case 'tools/list':
          result = {
            'tools': [
              {
                'name': 'snapshot',
                'description': 'Get the current widget tree as LLM-friendly JSON. '
                    'Returns pruned tree with type, label, key, bounds for each node.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'inspect',
                'description': 'Get detailed properties of a specific widget node.',
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
                'description': 'Tap a widget. Selector formats: '
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
                'description': 'Focus a text field by selector and enter text.',
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
                'description': 'Scroll a scrollable widget in a direction.',
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
                'description': 'Capture the current screen as PNG.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'hot_reload',
                'description': 'Trigger hot reload on the connected Flutter app.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {},
                },
              },
              {
                'name': 'evaluate',
                'description': 'Evaluate a Dart expression in the running app.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'expression': {'type': 'string', 'description': 'Dart expression'},
                  },
                  'required': ['expression'],
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

  await connection.disconnect();
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
      'inspect' => await inspectTool(connection, args['nodeId'] as String),
      'tap' => await tapTool(connection, args['selector'] as String, trace),
      'type_text' => await typeTextTool(
          connection, args['selector'] as String, args['text'] as String, trace),
      'scroll' => await scrollTool(
          connection, args['selector'] as String, args['direction'] as String, trace,
          amount: (args['amount'] as num?)?.toDouble() ?? 300.0),
      'screenshot' => await screenshotTool(connection, trace),
      'hot_reload' => await hotReloadTool(connection, trace),
      'evaluate' => await evaluateTool(connection, args['expression'] as String, trace),
      _ => {'error': 'Unknown tool: $tool'},
    };

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
