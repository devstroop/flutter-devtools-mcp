/// MCP server for Flutter UI automation via DevTools VM Service extensions.
///
/// This library exports the core modules used by the MCP server.
/// Tool implementations under `src/tools/` are intentionally NOT exported —
/// they are internal to the server binary (`bin/server.dart`) and not part
/// of the public API.
library flutter_devtools_mcp;

export 'src/connection.dart';
export 'src/selectors.dart';
export 'src/transform.dart';
export 'src/actions.dart';
export 'src/retry.dart';
export 'src/trace.dart';
