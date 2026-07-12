import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

/// Defines one MCP tool — its JSON-RPC schema and handler.
///
/// The handler receives tool arguments and returns a result map.
/// It should NOT touch stdin/stdout or parse JSON-RPC — the [McpServer]
/// handles all protocol concerns.
class ToolDef {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> args)
      handler;

  const ToolDef({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.handler,
  });
}

/// Thin MCP stdio server — reads JSON-RPC from stdin, dispatches to tools,
/// writes JSON-RPC responses to stdout.
///
/// Usage:
/// ```dart
/// void main() {
///   McpServer(
///     name: 'my_server',
///     version: '1.0.0',
///     tools: [snapshotTool, tapTool, ...],
///   ).run();
/// }
/// ```
class McpServer {
  final String name;
  final String version;
  final List<ToolDef> tools;
  final IOSink _out;

  McpServer({
    required this.name,
    required this.version,
    required this.tools,
    IOSink? outputSink,
  }) : _out = outputSink ?? stdout;

  /// Start reading stdin and responding. Blocks until stdin closes or exit is requested.
  Future<void> run() async {
    stderr.writeln('$name v$version ready — listening on stdio');

    await for (final line
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;

      try {
        final request = json.decode(line) as Map<String, dynamic>;
        await handleRequest(request);
      } catch (e, st) {
        stderr.writeln('[$name] Error processing line: $e\n$st');
        tryRespondError(line);
      }
    }
  }

  /// Handle a decoded JSON-RPC request.
  ///
  /// Package-visible for testing. Use [run()] in production.
  @visibleForTesting
  Future<void> handleRequest(Map<String, dynamic> request) async {
    final method = request['method'] as String?;
    final id = request['id'];

    switch (method) {
      case 'initialize':
        sendResponse(id, {
          'protocolVersion': '2024-11-05',
          'capabilities': {'tools': {}},
          'serverInfo': {'name': name, 'version': version},
        });

      case 'notifications/initialized':
        // Notification — no response
        break;

      case 'shutdown':
        sendResponse(id, {});

      case 'exit':
        sendResponse(id, {});
        exit(0);

      case 'ping':
        sendResponse(id, {});

      case 'resources/list':
        sendResponse(id, {'resources': []});

      case 'prompts/list':
        sendResponse(id, {'prompts': []});

      case 'tools/list':
        sendResponse(id, {
          'tools': tools
              .map((t) => {
                    'name': t.name,
                    'description': t.description,
                    'inputSchema': t.inputSchema,
                  })
              .toList(),
        });

      case 'tools/call':
        await handleToolCall(request, id);

      default:
        if (id != null) {
          sendErrorResponse(id, -32601, 'Method not found: $method');
        }
      // Unknown method without id = notification → ignore
    }
  }

  /// Handle a tools/call request.
  @visibleForTesting
  Future<void> handleToolCall(Map<String, dynamic> request, dynamic id) async {
    final rawParams = request['params'];
    final params = rawParams is Map
        ? Map<String, dynamic>.from(rawParams)
        : <String, dynamic>{};
    final toolName = params['name'] as String?;
    if (toolName == null) {
      sendErrorResponse(id, -32602, 'Missing required "name" parameter');
      return;
    }

    final tool = tools.cast<ToolDef?>().firstWhere(
          (t) => t!.name == toolName,
          orElse: () => null,
        );
    if (tool == null) {
      sendResponse(id, {
        'isError': true,
        'content': [
          {'type': 'text', 'text': 'Unknown tool: $toolName'}
        ],
      });
      return;
    }

    final rawArgs = params['arguments'];
    final toolArgs = rawArgs is Map
        ? Map<String, dynamic>.from(rawArgs)
        : <String, dynamic>{};

    try {
      final result = await tool.handler(toolArgs);

      // Screenshot tool returns _mcp_content_type: 'image' — wrap as MCP image
      if (result['_mcp_content_type'] == 'image') {
        final data = result['data'] as String? ?? '';
        final mime = result['mimeType'] as String? ?? 'image/png';
        sendResponse(id, {
          'content': [
            {'type': 'image', 'data': data, 'mimeType': mime}
          ],
        });
      } else {
        sendResponse(id, {
          'content': [
            {'type': 'text', 'text': json.encode(result)}
          ],
        });
      }
    } catch (e) {
      sendResponse(id, {
        'isError': true,
        'content': [
          {'type': 'text', 'text': 'Error: $e'}
        ],
      });
    }
  }

  /// Send a JSON-RPC success response to stdout.
  @visibleForTesting
  void sendResponse(dynamic id, Map<String, dynamic>? result) {
    _out.writeln(json.encode({
      'jsonrpc': '2.0',
      'id': id,
      if (result != null) 'result': result,
    }));
  }

  /// Send a JSON-RPC error response to stdout.
  @visibleForTesting
  void sendErrorResponse(dynamic id, int code, String message) {
    _out.writeln(json.encode({
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': code, 'message': message},
    }));
  }

  /// Try to extract an id from a (possibly malformed) JSON line and send an error.
  @visibleForTesting
  void tryRespondError(String rawLine) {
    try {
      final request = json.decode(rawLine) as Map<String, dynamic>;
      final id = request['id'];
      if (id != null) {
        sendErrorResponse(id, -32603, 'Internal error');
      }
    } catch (_) {
      // Malformed — nothing we can respond to
    }
  }
}
