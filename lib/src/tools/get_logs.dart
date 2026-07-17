import 'dart:async';

import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';
import '../trace.dart';

/// MCP tool: get_logs
///
/// Capture recent app output (stdout/stderr) from the running Flutter app.
/// Subscribes to the Stdout and Stderr VM service streams, collects messages
/// within a brief window, and returns them. Useful for reading print()
/// output, debug messages, and runtime warnings.
Future<Map<String, Object?>> getLogsImpl(
  FlutterConnection connection,
  TraceLog trace,
) async {
  final startTime = trace.start();
  final logs = <Map<String, Object?>>[];
  StreamSubscription<dynamic>? stdoutSub;
  StreamSubscription<dynamic>? stderrSub;
  StreamSubscription<dynamic>? loggingSub;

  try {
    // Subscribe to Stdout stream
    try {
      await connection.service.streamListen('Stdout');
    } catch (_) {
      // Already subscribed — that's fine
    }

    // Subscribe to Stderr stream
    try {
      await connection.service.streamListen('Stderr');
    } catch (_) {
      // Already subscribed
    }

    // Listen for stdout events
    stdoutSub = connection.service.onStdoutEvent.listen((event) {
      final bytes = event.bytes;
      if (bytes != null) {
        logs.add({
          'stream': 'stdout',
          'message': bytes,
          'timestamp': event.timestamp,
        });
      }
    });

    // Listen for stderr events
    stderrSub = connection.service.onStderrEvent.listen((event) {
      final bytes = event.bytes;
      if (bytes != null) {
        logs.add({
          'stream': 'stderr',
          'message': bytes,
          'timestamp': event.timestamp,
        });
      }
    });

    // Also capture logging events (dart:developer log())
    try {
      await connection.service.streamListen('Logging');
    } catch (_) {}

    loggingSub = connection.service.onLoggingEvent.listen((event) {
      final logRecord = event.logRecord;
      if (logRecord != null) {
        logs.add({
          'stream': 'logging',
          'message': logRecord.message?.valueAsString,
          'loggerName': logRecord.loggerName?.valueAsString,
          'level': logRecord.level,
          'timestamp': event.timestamp,
        });
      }
    });

    // Trigger a print to flush any pending output, then wait for events
    try {
      await connection.evaluate("print('')");
    } catch (_) {}

    // Give a window for events to arrive
    await Future.delayed(const Duration(milliseconds: 500));

    trace.complete(
      action: 'get_logs',
      startTimeMs: startTime,
      result: 'success',
    );

    return {
      'status': 'success',
      'logCount': logs.length,
      'logs': logs,
      if (logs.isEmpty)
        'message': 'No log output captured in the collection window.',
    };
  } catch (e) {
    trace.complete(
      action: 'get_logs',
      startTimeMs: startTime,
      result: 'error',
      error: e.toString(),
    );
    return {'status': 'error', 'error': e.toString()};
  } finally {
    // Ensure subscriptions are always cancelled, even on error
    await stdoutSub?.cancel();
    await stderrSub?.cancel();
    await loggingSub?.cancel();
  }
}

ToolDef createGetLogsTool() {
  return ToolDef(
    name: 'get_logs',
    description:
        'Capture recent app output (stdout/stderr) from the running Flutter app.',
    inputSchema: {
      'type': 'object',
      'properties': {},
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      return getLogsImpl(conn, TraceLog());
    },
  );
}
