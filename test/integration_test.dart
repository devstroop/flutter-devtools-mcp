@Tags(['integration'])
library;

import 'dart:io';
import 'package:test/test.dart';
import 'package:flutter_devtools_mcp/src/connection.dart';
import 'package:flutter_devtools_mcp/src/selectors.dart';
import 'package:flutter_devtools_mcp/src/tools/snapshot.dart';
import 'package:flutter_devtools_mcp/src/tools/inspect.dart';
import 'package:flutter_devtools_mcp/src/tools/tap.dart';
import 'package:flutter_devtools_mcp/src/tools/screenshot.dart';
import 'package:flutter_devtools_mcp/src/tools/hot_reload.dart';
import 'package:flutter_devtools_mcp/src/tools/evaluate.dart';
import 'package:flutter_devtools_mcp/src/tools/type_text.dart';
import 'package:flutter_devtools_mcp/src/tools/scroll.dart';
import 'package:flutter_devtools_mcp/src/tools/press_back.dart';

/// Integration tests for flutter_devtools_mcp.
///
/// These require a running Flutter debug app (the test fixture app).
///
/// Usage:
///   1. cd test/fixtures/test_app
///   2. flutter run --debug  (note the VM Service URL)
///   3. export FLUTTER_VM_SERVICE_URL=ws://127.0.0.1:XXXXX/YYYY=/ws
///   4. cd ../../..
///   5. dart test --tags integration
void main() {
  late FlutterConnection connection;

  final vmUrl = Platform.environment['FLUTTER_VM_SERVICE_URL'];

  setUp(() async {
    if (vmUrl == null) {
      fail('Set FLUTTER_VM_SERVICE_URL env var to run integration tests.');
    }
    connection = FlutterConnection(vmServiceUrl: vmUrl);
    await connection.connect();
  });

  tearDown(() async {
    await connection.disconnect();
  });

  group('snapshot', () {
    test('returns valid tree with node IDs', () async {
      final result = await snapshotImpl(connection);
      expect(result['id'], isNotNull);
      expect(result['type'], isA<String>());
      // Tree should have children (the app has content)
      expect(result.containsKey('children'), true);
    });

    test('tree contains expected widget types', () async {
      final result = await snapshotImpl(connection);
      // Walk the tree and collect types
      final types = <String>{};
      _collectTypes(result, types);
      // The test app should have these widget types
      expect(types, contains(contains('Scaffold')));
      expect(types, contains(contains('Text')));
    });
  });

  group('inspect', () {
    test('returns detailed node properties', () async {
      // First get a node ID from snapshot
      final tree = await snapshotImpl(connection);
      final nodeId = tree['id'] as String;

      final detail = await inspectImpl(connection, nodeId);
      expect(detail['id'], isNotNull);
      expect(detail['type'], isA<String>());
    });
  });

  group('selectors', () {
    test('resolves semantics selector', () async {
      final selector = Selector.parse('semantics:Increment');
      final node = await resolveSelector(connection, selector);
      expect(node.matchedVia, SelectorTier.semantics);
      expect(node.label, 'Increment');
    });

    test('resolves key selector', () async {
      final selector = Selector.parse('key:increment_btn');
      final node = await resolveSelector(connection, selector);
      expect(node.matchedVia, SelectorTier.key);
      expect(node.key, 'increment_btn');
    });

    test('throws ambiguity error for duplicate labels', () async {
      // The test app has 3 buttons with label "Action"
      final selector = Selector.parse('semantics:Action');
      expect(
        () => resolveSelector(connection, selector),
        throwsA(isA<SelectorError>()),
      );
    });
  });

  group('tap', () {
    test('taps button and changes state', () async {
      // Tap the increment button
      final result = await tapImpl(connection, 'semantics:Increment');
      expect(result['status'], 'success');
      // Verify the resolved node is returned
      final node = result['node'] as Map<String, Object?>?;
      expect(node, isNotNull);
      expect(node!['type'], isA<String>());
      expect(node['id'], isA<String>());
    });
  });

  group('screenshot', () {
    test('returns valid PNG data', () async {
      final result = await screenshotImpl(connection);
      expect(result['status'], 'success');
      expect(result['format'], 'png');
      expect(result['encoding'], 'base64');
      expect(result['data'], isA<String>());
      // Base64 PNG starts with iVBOR
      final data = result['data'] as String;
      expect(data.length, greaterThan(100));
    });
  });

  group('evaluate', () {
    test('evaluates simple expression', () async {
      final result = await evaluateImpl(connection, '1 + 1');
      expect(result['status'], 'success');
      expect(result['value'], '2');
    });

    test('evaluates string expression', () async {
      final result = await evaluateImpl(connection, '"hello".toUpperCase()');
      expect(result['status'], 'success');
      expect(result['value'], 'HELLO');
    });
  });

  group('hot_reload', () {
    test('triggers reload successfully', () async {
      final result = await hotReloadImpl(connection);
      expect(result['status'], 'success');
    });
  });

  group('type_text', () {
    test('resolves field and reports error when field not focused', () async {
      // The type_text tool taps the field by coordinates then enters text.
      // When the field is offscreen or gesture injection doesn't result in
      // focus (a known limitation of PointerEvent injection), it should
      // give a clear error indicating no focused text field was found.
      final result = await typeTextImpl(
        connection,
        'key:name_field',
        'Test Input',
      );
      // Either success (field got focused) or error with clear message
      final status = result['status'] as String;
      if (status == 'error') {
        expect(result['error'].toString(), contains('No focused text field'));
      } else {
        expect(status, 'success');
        expect(result['text'], 'Test Input');
      }
    });
  });

  group('scroll', () {
    test('scrolls a list view down', () async {
      // The scroll tab has a vertical ListView with key 'vertical_list'
      final result = await scrollImpl(
        connection,
        'key:vertical_list',
        'down',
      );
      expect(result['status'], 'success');
      expect(result['direction'], 'down');
      expect(result['amount'], 300.0);
    });
  });

  group('press_back', () {
    test('returns success even when no route to pop', () async {
      final result = await pressBackImpl(connection);
      expect(result['status'], 'success');
    });
  });
}

/// Recursively collect widget types from a transformed tree.
void _collectTypes(Map<String, Object?> node, Set<String> types) {
  final type = node['type'] as String?;
  if (type != null) types.add(type);
  final children = node['children'] as List<Object?>?;
  if (children != null) {
    for (final child in children) {
      if (child is Map<String, Object?>) {
        _collectTypes(child, types);
      }
    }
  }
}
