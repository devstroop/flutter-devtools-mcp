import 'dart:async';
import 'package:test/test.dart';
import 'package:flutter_devtools_mcp/src/retry.dart';

void main() {
  group('withRetry', () {
    test('returns on first success', () async {
      var calls = 0;
      final result = await withRetry(() async {
        calls++;
        return 42;
      }, description: 'test');
      expect(result, 42);
      expect(calls, 1);
    });

    test('retries until success', () async {
      var calls = 0;
      final result = await withRetry(
        () async {
          calls++;
          if (calls < 3) throw StateError('not yet');
          return 'done';
        },
        config: const RetryConfig(
          timeout: Duration(seconds: 2),
          pollInterval: Duration(milliseconds: 10),
        ),
        description: 'retry-test',
      );
      expect(result, 'done');
      expect(calls, 3);
    });

    test('throws TimeoutException when timeout expires', () async {
      await expectLater(
        withRetry(
          () async {
            throw StateError('always fails');
          },
          config: const RetryConfig(
            timeout: Duration(milliseconds: 100),
            pollInterval: Duration(milliseconds: 20),
          ),
          description: 'timeout-test',
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('includes description in timeout message', () async {
      Object? caught;
      try {
        await withRetry(
          () async {
            throw StateError('boom');
          },
          config: const RetryConfig(
            timeout: Duration(milliseconds: 50),
            pollInterval: Duration(milliseconds: 10),
          ),
          description: 'my-operation',
        );
      } on TimeoutException catch (e) {
        caught = e;
      }
      expect(caught, isA<TimeoutException>());
      final msg = (caught as TimeoutException).message!;
      expect(msg, contains('my-operation'));
      expect(msg, contains('boom'));
    });
  });
}
