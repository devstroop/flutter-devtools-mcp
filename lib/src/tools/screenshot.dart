import 'dart:convert';

import '../connection.dart';
import '../trace.dart';

/// MCP tool: screenshot
///
/// Capture the current screen as base64-encoded PNG.
Future<Map<String, Object?>> screenshotTool(
  FlutterConnection connection,
  TraceLog trace,
) async {
  final startTime = trace.start();

  try {
    final response = await connection.screenshot();
    final bytes = response.json?['screenshot'] as String?;

    trace.complete(
      action: 'screenshot',
      startTimeMs: startTime,
      result: 'success',
    );

    return {
      'status': 'success',
      'format': 'png',
      'encoding': 'base64',
      if (bytes != null) 'data': bytes,
    };
  } catch (e) {
    trace.complete(
      action: 'screenshot',
      startTimeMs: startTime,
      result: 'error',
      error: e.toString(),
    );
    rethrow;
  }
}
