import 'package:test/test.dart';
import 'package:flutter_devtools_mcp/src/trace.dart';

void main() {
  group('TraceEntry', () {
    test('calculates durationMs', () {
      final entry = TraceEntry(
        action: 'tap',
        startTimeMs: 1000,
        endTimeMs: 1150,
        result: 'success',
      );
      expect(entry.durationMs, 150);
    });

    test('toJson includes all fields', () {
      final entry = TraceEntry(
        action: 'tap',
        target: 'Submit',
        selector: 'semantics:Submit',
        resolvedNode: {'id': 'v1', 'type': 'Button'},
        bounds: {'x': 0, 'y': 0, 'w': 100, 'h': 48},
        retryCount: 2,
        startTimeMs: 1000,
        endTimeMs: 1200,
        result: 'success',
      );
      final json = entry.toJson();
      expect(json['action'], 'tap');
      expect(json['target'], 'Submit');
      expect(json['selector'], 'semantics:Submit');
      expect(json['resolvedNode'], isNotNull);
      expect(json['bounds'], isNotNull);
      expect(json['retryCount'], 2);
      expect(json['durationMs'], 200);
      expect(json['result'], 'success');
      expect(json.containsKey('error'), false);
    });

    test('toJson includes error when present', () {
      final entry = TraceEntry(
        action: 'tap',
        startTimeMs: 1000,
        endTimeMs: 1050,
        result: 'error',
        error: 'Node not found',
      );
      final json = entry.toJson();
      expect(json['error'], 'Node not found');
    });
  });

  group('TraceLog', () {
    test('start returns current time in ms', () {
      final log = TraceLog();
      final start = log.start();
      expect(start, greaterThan(0));
      expect(start, closeTo(DateTime.now().millisecondsSinceEpoch, 100));
    });

    test('complete adds entry to log', () {
      final log = TraceLog();
      final start = log.start();
      log.complete(
        action: 'screenshot',
        startTimeMs: start,
        result: 'success',
      );
      expect(log.entries, hasLength(1));
      expect(log.entries.first.action, 'screenshot');
    });

    test('toJson serializes all entries', () {
      final log = TraceLog();
      log.complete(
        action: 'tap', startTimeMs: 1000, result: 'success',
      );
      log.complete(
        action: 'screenshot', startTimeMs: 2000, result: 'success',
      );
      final json = log.toJson();
      expect(json, hasLength(2));
      expect(json[0]['action'], 'tap');
      expect(json[1]['action'], 'screenshot');
    });

    test('clear removes all entries', () {
      final log = TraceLog();
      log.complete(action: 'tap', startTimeMs: 1000, result: 'success');
      log.clear();
      expect(log.entries, isEmpty);
    });

    test('entries list is unmodifiable', () {
      final log = TraceLog();
      expect(() => log.entries.add(TraceEntry(
        action: 'x', startTimeMs: 0, endTimeMs: 0, result: 'x',
      )), throwsA(isA<UnsupportedError>()));
    });
  });
}
