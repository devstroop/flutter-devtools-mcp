import '../connection_factory.dart';
import '../mcp_transport.dart';
import 'launch_state.dart';

/// MCP tool impl: stop_app
///
/// Stop a running app launched via the launch tool.
ToolDef createStopAppTool(ConnectionFactory factory) {
  return ToolDef(
    name: 'stop_app',
    description: 'Stop a running app launched via the launch tool. '
        'Kills the flutter run process and disconnects from the VM Service.',
    inputSchema: {
      'type': 'object',
      'properties': {},
    },
    handler: (args) async {
      if (launchState.process == null) {
        return {
          'isError': true,
          'content': [
            {
              'type': 'text',
              'text': 'Error: No app has been launched via the launch tool.',
            },
          ],
        };
      }
      final stoppedPath = launchState.projectPath;
      killLaunchedProcess();
      launchState.projectPath = null;
      launchState.log.add('App stopped by stop_app tool');
      return {
        'content': [
          {
            'type': 'text',
            'text': '{"status":"stopped","projectPath":"$stoppedPath"}',
          },
        ],
      };
    },
  );
}
