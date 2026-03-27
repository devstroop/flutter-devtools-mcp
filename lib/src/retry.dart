import 'dart:async';
import 'package:logging/logging.dart';

final _log = Logger('Retry');

/// Auto-retry configuration.
class RetryConfig {
  final Duration timeout;
  final Duration pollInterval;
  final int stabilityFrames;

  const RetryConfig({
    this.timeout = const Duration(seconds: 5),
    this.pollInterval = const Duration(milliseconds: 100),
    this.stabilityFrames = 2,
  });
}

/// Retry a function until it succeeds or timeout expires.
///
/// The function should return a result on success or throw on failure.
/// Between attempts, waits [RetryConfig.pollInterval].
///
/// This is the core retry primitive — used by action tools to handle
/// "eventually consistent UI" without detecting Flutter idle state.
Future<T> withRetry<T>(
  Future<T> Function() fn, {
  RetryConfig config = const RetryConfig(),
  String? description,
}) async {
  final deadline = DateTime.now().add(config.timeout);
  var attempt = 0;
  Object? lastError;

  while (DateTime.now().isBefore(deadline)) {
    attempt++;
    try {
      final result = await fn();
      if (attempt > 1) {
        _log.fine('$description succeeded after $attempt attempts');
      }
      return result;
    } catch (e) {
      lastError = e;
      _log.finer('$description attempt $attempt failed: $e');
      await Future<void>.delayed(config.pollInterval);
    }
  }

  throw TimeoutException(
    '${description ?? "Operation"} failed after $attempt attempts '
    '(${config.timeout.inMilliseconds}ms). Last error: $lastError',
    config.timeout,
  );
}
