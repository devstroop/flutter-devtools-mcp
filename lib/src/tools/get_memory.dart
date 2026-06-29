import '../connection.dart';
import '../connection_factory.dart';
import '../mcp_transport.dart';
import '../trace.dart';

/// MCP tool: get_memory
///
/// Get memory usage of the Flutter app's main isolate.
/// Returns heap used/capacity and external usage in bytes.
Future<Map<String, Object?>> getMemoryImpl(
  FlutterConnection connection,
  TraceLog trace,
) async {
  final startTime = trace.start();

  try {
    final usage = await connection.service.getMemoryUsage(
      connection.isolateId,
    );

    trace.complete(
      action: 'get_memory',
      startTimeMs: startTime,
      result: 'success',
    );

    return {
      'status': 'success',
      'heapUsedBytes': usage.heapUsage,
      'heapCapacityBytes': usage.heapCapacity,
      'externalUsageBytes': usage.externalUsage,
      'heapUsedMB': _bytesToMB(usage.heapUsage),
      'heapCapacityMB': _bytesToMB(usage.heapCapacity),
      'externalUsageMB': _bytesToMB(usage.externalUsage),
    };
  } catch (e) {
    trace.complete(
      action: 'get_memory',
      startTimeMs: startTime,
      result: 'error',
      error: e.toString(),
    );
    return {'status': 'error', 'error': e.toString()};
  }
}

String _bytesToMB(int? bytes) {
  if (bytes == null) return 'unknown';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

ToolDef createGetMemoryTool(ConnectionFactory factory) {
  return ToolDef(
    name: 'get_memory',
    description: 'Get memory usage of the Flutter app — heap used/capacity, external.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'vmServiceUrl': {
          'type': 'string',
          'description': 'VM Service WebSocket URL (optional — auto-discovers via mDNS if omitted)',
        },
      },
    },
    handler: (args) async {
      final conn = await factory.getConnection(args['vmServiceUrl'] as String?);
      return getMemoryImpl(conn, TraceLog());
    },
  );
}
