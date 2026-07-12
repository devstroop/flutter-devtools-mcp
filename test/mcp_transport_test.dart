import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:flutter_devtools_mcp/src/mcp_transport.dart';

/// A synchronous [IOSink] that appends to a [List<String>].
///
/// Unlike [StreamController]-based sinks, writes are immediately available
/// in [lines] — no microtask delay. This is essential for testing because
/// [McpServer.handleRequest] writes responses synchronously.
class SyncSink implements IOSink {
  final List<String> lines;

  SyncSink({List<String>? lines}) : lines = lines ?? [];

  @override
  void writeln([Object? obj = '']) => lines.add(obj.toString());
  @override
  void write(Object? obj) => lines.add(obj.toString());
  @override
  void writeAll(Iterable<Object?> objects, [String sep = '']) =>
      lines.add(objects.join(sep));
  @override
  void writeCharCode(int charCode) => lines.add(String.fromCharCode(charCode));
  @override
  void add(List<int> data) => lines.add(utf8.decode(data));
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<List<int>> stream) async {}
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
  @override
  Encoding get encoding => utf8;
  @override
  set encoding(Encoding encoding) {}
  @override
  Future<void> get done => Future.value();
}

/// Test harness that captures [McpServer] responses via an injectable
/// synchronous output sink.
///
/// Usage:
/// ```dart
/// final h = Harness(tools: [...]);
/// h.server.handleRequest({'method': 'tools/list', 'id': 1});
/// final response = h.nextResponse();
/// ```
class Harness {
  final McpServer server;
  final SyncSink sink;
  final List<Map<String, dynamic>> responses = [];

  Harness._({required this.server, required this.sink});

  /// Create a harness with the given tools.
  factory Harness.create({required List<ToolDef> tools}) {
    final sink = SyncSink();
    final server = McpServer(
      name: 'test_server',
      version: '1.0.0',
      tools: tools,
      outputSink: sink,
    );
    return Harness._(server: server, sink: sink);
  }

  /// Send a request and await the response.
  ///
  /// Parses raw lines from the sink into JSON-RPC response maps.
  /// [handleRequest] is async (it awaits tool handlers for tools/call),
  /// so this method awaits it before collecting responses.
  Future<Map<String, dynamic>> request(Map<String, dynamic> req) async {
    final before = sink.lines.length;
    await server.handleRequest(req);

    // Collect any new lines written by handleRequest
    final newLines = sink.lines.sublist(before);
    for (final line in newLines) {
      if (line.trim().isNotEmpty) {
        try {
          responses.add(json.decode(line) as Map<String, dynamic>);
        } catch (_) {}
      }
    }

    if (responses.isEmpty) {
      throw StateError('No response captured for request: ${req['method']}');
    }
    return responses.removeAt(0);
  }

  /// Check if there are pending responses.
  bool get hasResponse => responses.isNotEmpty;

  /// Dispose the harness.
  void dispose() {
    sink.close();
  }
}

void main() {
  group('ToolDef', () {
    test('constructs and exposes fields', () {
      final tool = ToolDef(
        name: 'test_tool',
        description: 'A test tool',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (_) async => {'result': 'ok'},
      );
      expect(tool.name, 'test_tool');
      expect(tool.description, 'A test tool');
    });

    test('handler can be invoked', () async {
      final tool = ToolDef(
        name: 'echo',
        description: '',
        inputSchema: {},
        handler: (args) async => {'echoed': args['msg']},
      );
      final result = await tool.handler({'msg': 'hello'});
      expect(result['echoed'], 'hello');
    });

    test('handler that throws propagates error', () async {
      final tool = ToolDef(
        name: 'fail',
        description: '',
        inputSchema: {},
        handler: (_) async => throw StateError('boom'),
      );
      expect(() => tool.handler({}), throwsA(isA<StateError>()));
    });
  });

  group('McpServer.handleRequest — protocol methods', () {
    late Harness harness;

    setUp(() {
      harness = Harness.create(tools: [
        ToolDef(
          name: 'echo',
          description: 'Echoes back arguments',
          inputSchema: {
            'type': 'object',
            'properties': {
              'msg': {'type': 'string'},
            },
            'required': ['msg'],
          },
          handler: (args) async => {'echoed': args['msg']},
        ),
        ToolDef(
          name: 'failing_tool',
          description: 'Always throws',
          inputSchema: {'type': 'object', 'properties': {}},
          handler: (_) async => throw StateError('Intentional failure'),
        ),
        ToolDef(
          name: 'image_tool',
          description: 'Returns an image',
          inputSchema: {'type': 'object', 'properties': {}},
          handler: (_) async => {
            '_mcp_content_type': 'image',
            'data': 'iVBORw0KGgo=',
            'mimeType': 'image/png',
          },
        ),
      ]);
    });

    tearDown(() => harness.dispose());

    test('initialize returns protocol version and server info', () async {
      final response = await harness.request({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
      });
      expect(response['id'], 1);
      expect(response['result']['protocolVersion'], '2024-11-05');
      expect(response['result']['serverInfo']['name'], 'test_server');
      expect(response['result']['serverInfo']['version'], '1.0.0');
    });

    test('tools/list returns registered tool schemas', () async {
      final response = await harness.request({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/list',
      });
      final tools = response['result']['tools'] as List;
      expect(tools, hasLength(3));
      expect(tools[0]['name'], 'echo');
      expect(tools[1]['name'], 'failing_tool');
      expect(tools[2]['name'], 'image_tool');
      // Each tool has schema info
      for (final t in tools) {
        expect(t['description'], isA<String>());
        expect(t['inputSchema'], isA<Map<String, dynamic>>());
      }
    });

    test('tools/call dispatches to correct handler', () async {
      final response = await harness.request({
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': {
          'name': 'echo',
          'arguments': {'msg': 'hello'}
        },
      });
      final content = response['result']['content'] as List;
      final text = json.decode(content[0]['text'] as String) as Map;
      expect((text as Map<String, dynamic>)['echoed'], 'hello');
    });

    test('tools/call with unknown tool returns error', () async {
      final response = await harness.request({
        'jsonrpc': '2.0',
        'id': 4,
        'method': 'tools/call',
        'params': {'name': 'nonexistent', 'arguments': {}},
      });
      expect(response['result']['isError'], true);
      final text = response['result']['content'][0]['text'] as String;
      expect(text, contains('Unknown tool'));
    });

    test('tools/call with failing handler returns error', () async {
      final response = await harness.request({
        'jsonrpc': '2.0',
        'id': 5,
        'method': 'tools/call',
        'params': {'name': 'failing_tool', 'arguments': {}},
      });
      expect(response['result']['isError'], true);
      final text = response['result']['content'][0]['text'] as String;
      expect(text, contains('Error'));
    });

    test('tools/call without name parameter returns -32602 error', () async {
      final response = await harness.request({
        'jsonrpc': '2.0',
        'id': 6,
        'method': 'tools/call',
        'params': {'arguments': {}},
      });
      expect(response['error']['code'], -32602);
      expect(response['error']['message'], contains('name'));
    });

    test('unknown method returns -32601 error', () async {
      final response = await harness.request({
        'jsonrpc': '2.0',
        'id': 7,
        'method': 'unknown_method',
      });
      expect(response['error']['code'], -32601);
      expect(response['error']['message'], contains('unknown_method'));
    });

    test('ping returns empty result', () async {
      final response = await harness.request({
        'jsonrpc': '2.0',
        'id': 8,
        'method': 'ping',
      });
      expect(response['id'], 8);
      expect(response['result'], isNotNull);
    });

    test('shutdown returns empty result', () async {
      final response = await harness.request({
        'jsonrpc': '2.0',
        'id': 9,
        'method': 'shutdown',
      });
      expect(response['id'], 9);
      expect(response['result'], isNotNull);
    });

    test('notifications/initialized produces no response', () async {
      await harness.server.handleRequest({
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      });
      expect(harness.hasResponse, false);
    });

    test('unknown method without id produces no response (notification)',
        () async {
      await harness.server.handleRequest({
        'jsonrpc': '2.0',
        'method': 'some_notification',
      });
      expect(harness.hasResponse, false);
    });
  });

  group('McpServer.handleRequest — image content wrapping', () {
    test('tool with _mcp_content_type wraps as MCP image', () async {
      final h = Harness.create(tools: [
        ToolDef(
          name: 'screenshot',
          description: '',
          inputSchema: {},
          handler: (_) async => {
            '_mcp_content_type': 'image',
            'data': 'iVBORw0KGgo=',
            'mimeType': 'image/png',
          },
        ),
      ]);

      final response = await h.request({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {'name': 'screenshot', 'arguments': {}},
      });
      final content = response['result']['content'] as List;
      expect(content[0]['type'], 'image');
      expect(content[0]['data'], 'iVBORw0KGgo=');
      expect(content[0]['mimeType'], 'image/png');

      h.dispose();
    });

    test('tool without _mcp_content_type wraps as text', () async {
      final h = Harness.create(tools: [
        ToolDef(
          name: 'plain',
          description: '',
          inputSchema: {},
          handler: (_) async => {'status': 'ok'},
        ),
      ]);

      final response = await h.request({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {'name': 'plain', 'arguments': {}},
      });
      final content = response['result']['content'] as List;
      expect(content[0]['type'], 'text');
      final parsed = json.decode(content[0]['text'] as String) as Map;
      expect(parsed['status'], 'ok');

      h.dispose();
    });
  });

  group('McpServer.handleRequest — resources and prompts', () {
    test('resources/list returns empty list', () async {
      final h = Harness.create(tools: []);
      final response = await h.request({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'resources/list',
      });
      expect(response['result']['resources'], []);
      h.dispose();
    });

    test('prompts/list returns empty list', () async {
      final h = Harness.create(tools: []);
      final response = await h.request({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'prompts/list',
      });
      expect(response['result']['prompts'], []);
      h.dispose();
    });
  });
}
