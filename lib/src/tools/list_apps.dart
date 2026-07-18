import 'dart:convert';

import '../mcp_transport.dart';
import '../registry.dart';

/// MCP tool: list_apps
///
/// Lists all Flutter apps that have been connected to this MCP server,
/// showing whether each is currently active (connected) or inactive.
/// Entries persist across server restarts via the registry file at
/// ~/.flutter_devtools_mcp/registry.json.
ToolDef createListAppsTool() {
  return ToolDef(
    name: 'list_apps',
    description:
        'List all Flutter apps that have been connected to this MCP server, '
        'including their VM Service URLs, project paths, and connection status. '
        'Entries persist across server restarts in ~/.flutter_devtools_mcp/registry.json. '
        'Use this to see which apps are still running or to pick a URL for the connect tool.',
    inputSchema: {
      'type': 'object',
      'properties': {},
    },
    handler: (args) async {
      final registry = Registry.instance;
      final entries = registry.entries;
      return {
        'content': [
          {
            'type': 'text',
            'text': entries.isEmpty
                ? '[]'
                : jsonEncode(entries.map((e) => e.toToolResult()).toList()),
          },
        ],
      };
    },
  );
}
