import 'dart:convert';

import '../connection.dart';
import '../connection_factory.dart';
import '../mcp_transport.dart';
import '../trace.dart';

/// MCP tool impl: get_parent_chain
///
/// Get the parent chain (ancestors) of a widget node, from the node up to
/// the root. Useful for understanding where a widget sits in the tree
/// hierarchy and what constraints/themes wrap it.
Future<Map<String, Object?>> getParentChainImpl(
  FlutterConnection connection,
  String nodeId,
  TraceLog trace,
) async {
  final startTime = trace.start();

  try {
    final response = await connection.service.callServiceExtension(
      'ext.flutter.inspector.getParentChain',
      isolateId: connection.isolateId,
      args: {
        'arg': nodeId,
        'objectGroup': 'mcp-parent-chain',
      },
    );

    final rawChain = response.json?['parentChain'];
    // parentChain arrives as a list of node summaries from child → root
    List<Map<String, Object?>> chain = [];

    if (rawChain is List) {
      for (final entry in rawChain) {
        if (entry is Map) {
          final node = entry['node'];
          if (node is Map<String, Object?>) {
            chain.add({
              'valueId': node['valueId'],
              'type': node['description'] ?? node['widgetRuntimeType'],
              if (node['creationLocation'] != null)
                'location': node['creationLocation'],
            });
          } else if (node is String) {
            // Sometimes the node is a JSON string
            try {
              final parsed = json.decode(node) as Map<String, Object?>;
              chain.add({
                'valueId': parsed['valueId'],
                'type': parsed['description'] ?? parsed['widgetRuntimeType'],
              });
            } catch (_) {
              chain.add({'raw': node});
            }
          } else {
            chain.add({'raw': entry.toString()});
          }
        }
      }
    }

    trace.complete(
      action: 'get_parent_chain',
      startTimeMs: startTime,
      target: nodeId,
      result: 'success',
    );

    return {
      'status': 'success',
      'nodeId': nodeId,
      'depth': chain.length,
      'parentChain': chain,
    };
  } catch (e) {
    trace.complete(
      action: 'get_parent_chain',
      startTimeMs: startTime,
      target: nodeId,
      result: 'error',
      error: e.toString(),
    );
    return {'status': 'error', 'error': e.toString()};
  }
}

ToolDef createGetParentChainTool(ConnectionFactory factory) {
  return ToolDef(
    name: 'get_parent_chain',
    description: 'Get the parent chain (ancestors) of a widget node.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'nodeId': {'type': 'string', 'description': 'Node ID from snapshot'},
        'vmServiceUrl': {
          'type': 'string',
          'description': 'VM Service WebSocket URL (optional — auto-discovers via mDNS if omitted)',
        },
      },
      'required': ['nodeId'],
    },
    handler: (args) async {
      final conn = await factory.getConnection(args['vmServiceUrl'] as String?);
      return getParentChainImpl(conn, args['nodeId'] as String, TraceLog());
    },
  );
}
