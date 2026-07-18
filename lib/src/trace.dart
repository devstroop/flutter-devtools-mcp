import 'package:logging/logging.dart';

final _log = Logger('Trace');

/// A single traced action in an MCP session.
class TraceEntry {
  final String action;
  final String? target;
  final String? selector;
  final Map<String, Object?>? resolvedNode;
  final Map<String, Object?>? bounds;
  final int retryCount;
  final int startTimeMs;
  final int endTimeMs;
  final String result; // 'success' | 'error'
  final String? error;

  TraceEntry({
    required this.action,
    this.target,
    this.selector,
    this.resolvedNode,
    this.bounds,
    this.retryCount = 0,
    required this.startTimeMs,
    required this.endTimeMs,
    required this.result,
    this.error,
  });

  int get durationMs => endTimeMs - startTimeMs;

  Map<String, Object?> toJson() => {
        'action': action,
        if (target != null) 'target': target,
        if (selector != null) 'selector': selector,
        if (resolvedNode != null) 'resolvedNode': resolvedNode,
        if (bounds != null) 'bounds': bounds,
        'retryCount': retryCount,
        'startTime': startTimeMs,
        'endTime': endTimeMs,
        'durationMs': durationMs,
        'result': result,
        if (error != null) 'error': error,
      };
}

/// Maintains an ordered list of trace entries for the current session.
class TraceLog {
  final _entries = <TraceEntry>[];

  List<TraceEntry> get entries => List.unmodifiable(_entries);

  void add(TraceEntry entry) {
    _entries.add(entry);
    _log.fine('[${entry.action}] ${entry.result} (${entry.durationMs}ms)');
  }

  /// Start a new trace entry. Returns [startTimeMs] for pairing with [complete].
  int start() => DateTime.now().millisecondsSinceEpoch;

  /// Complete a trace entry and add it to the log.
  void complete({
    required String action,
    required int startTimeMs,
    String? target,
    String? selector,
    Map<String, Object?>? resolvedNode,
    Map<String, Object?>? bounds,
    int retryCount = 0,
    required String result,
    String? error,
  }) {
    add(TraceEntry(
      action: action,
      target: target,
      selector: selector,
      resolvedNode: resolvedNode,
      bounds: bounds,
      retryCount: retryCount,
      startTimeMs: startTimeMs,
      endTimeMs: DateTime.now().millisecondsSinceEpoch,
      result: result,
      error: error,
    ));
  }

  List<Map<String, Object?>> toJson() => [
        for (final entry in _entries) entry.toJson(),
      ];

  void clear() => _entries.clear();
}
