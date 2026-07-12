import 'dart:convert';
import '../connection_factory.dart';
import '../mcp_transport.dart';
import 'launch_state.dart';

/// MCP tool impl: launch_status
///
/// Check the status of the most recently launched app process.
ToolDef createLaunchStatusTool(ConnectionFactory factory) {
  return ToolDef(
    name: 'launch_status',
    description: 'Check the status of the most recently launched app process. '
        'Returns whether the process is alive, the PID, '
        'project path, and recent log output.',
    inputSchema: {
      'type': 'object',
      'properties': {},
    },
    handler: (args) async {
      final alive = launchState.process != null && launchState.alive;
      final map = <String, Object?>{
        'alive': alive,
        'projectPath': launchState.projectPath,
        'logLines': launchState.log.length,
        'recentLog': launchState.log.join('\n'),
      };
      if (launchState.process != null && alive) {
        map['pid'] = launchState.process!.pid;
      }
      return {
        'content': [
          {'type': 'text', 'text': json.encode(map)},
        ],
      };
    },
  );
}
