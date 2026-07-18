import 'package:logging/logging.dart';

import '../connection.dart';
import '../current_connection.dart';
import '../mcp_transport.dart';

final _log = Logger('GetMemory');

/// MCP tool: get_memory
///
/// Get memory usage of the Flutter app's main isolate.
Future<Map<String, Object?>> getMemoryImpl(
  FlutterConnection connection,
) async {
  try {
    final usage = await connection.service.getMemoryUsage(
      connection.isolateId,
    );

    _log.info('Memory: ${_bytesToMB(usage.heapUsage)} heap');

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
    _log.warning('Get memory failed: $e');
    return {'status': 'error', 'error': e.toString()};
  }
}

String _bytesToMB(int? bytes) {
  if (bytes == null) return 'unknown';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

ToolDef createGetMemoryTool() {
  return ToolDef(
    name: 'get_memory',
    description:
        'Get memory usage of the Flutter app — heap used/capacity, external.',
    inputSchema: {
      'type': 'object',
      'properties': {},
    },
    handler: (args) async {
      final conn = await CurrentConnection.get();
      return getMemoryImpl(conn);
    },
  );
}
