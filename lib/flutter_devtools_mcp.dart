/// MCP server for Flutter UI automation via DevTools VM Service extensions.
///
/// This library exports the core modules used by the MCP server.
/// Tool implementations under `src/tools/` export both raw impl functions
/// (for testing) and `create*Tool()` factory functions.
library flutter_devtools_mcp;

export 'src/connection.dart';
export 'src/current_connection.dart';
export 'src/mcp_transport.dart';
export 'src/selectors.dart';
export 'src/transform.dart';
export 'src/actions.dart';
export 'src/retry.dart';
export 'src/registry.dart';
