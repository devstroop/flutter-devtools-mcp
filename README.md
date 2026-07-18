# Flutter Devtools MCP

An [MCP server](https://modelcontextprotocol.io/) that lets AI agents see and interact with
your running Flutter app — tap buttons, type text, scroll, take screenshots, hot reload,
and more — all through the VM Service protocol.

## Quick Start

**Prerequisites:** [Flutter SDK](https://docs.flutter.dev/get-started/install) (includes Dart)

```bash
git clone https://github.com/user/flutter_devtools_mcp.git
cd flutter_devtools_mcp
dart pub get
dart compile exe bin/server.dart -o bin/flutter_devtools_mcp_server
```

Add to your editor's MCP config:

**VS Code** (`.vscode/mcp.json`):
```jsonc
{
  "servers": {
    "flutter": {
      "command": "/absolute/path/to/flutter_devtools_mcp/bin/flutter_devtools_mcp_server",
      "args": []
    }
  }
}
```

**Claude Desktop** (`claude_desktop_config.json`):
```json
{
  "mcpServers": {
    "flutter": {
      "command": "/absolute/path/to/flutter_devtools_mcp/bin/flutter_devtools_mcp_server"
    }
  }
}
```

Restart your editor / MCP client and the tools are ready.

---

## Tool Reference

### Connection

| Tool | Arguments | Description |
|---|---|---|
| `connect` | `vmServiceUrl` (required) | Connect via VM Service URL from `flutter run` output |
| `disconnect` | — | Close connection, kill managed `flutter run` if any |
| `status` | — | `{"connected": true/false}` |
| `list_apps` | — | List all apps in the persistent registry with connection status |
| `flutter_run` | `platform` (required), `workingDirectory` | Start and auto-connect in one step |

### Inspection

| Tool | Arguments | Description |
|---|---|---|
| `widget_tree` | — | Full widget tree as JSON (types, labels, keys, bounds, children) |
| `inspect` | `nodeId` (required) | Deep properties of one widget node |
| `get_parent_chain` | `nodeId` (required) | Ancestor chain from node to root |
| `get_render_tree` | — | Render object tree as text (layout, constraints, sizes) |
| `get_layer_tree` | — | Compositing layer tree — diagnose saveLayer/opacity overhead |
| `dump_semantics` | — | Accessibility/semantics tree in traversal order |

### Interaction

| Tool | Arguments | Description |
|---|---|---|
| `tap` | `selector` (required) | Tap widget by selector |
| `type_text` | `selector` (required), `text` (required) | Focus field and enter text |
| `scroll` | `selector` (required), `direction`, `amount` | Scroll a scrollable widget |
| `press_back` | — | Pop the top navigator route |
| `screenshot` | — | Capture screen as base64 PNG |

### Development

| Tool | Arguments | Description |
|---|---|---|
| `hot_reload` | — | Apply code changes, preserve state |
| `hot_restart` | — | Full restart, reset app state |
| `evaluate` | `expression` (required) | Run arbitrary Dart expression in the app |
| `get_errors` | — | Get Flutter framework errors (build errors, flex overflows, etc.) |
| `get_logs` | — | Capture recent stdout/stderr/log() output |
| `get_memory` | — | Heap and external memory usage of the main isolate |

### Theme & Platform

| Tool | Arguments | Description |
|---|---|---|
| `toggle_dark_mode` | `enable` (bool) | Switch between light and dark mode |
| `toggle_platform` | `platform` (required) | Override target platform (ios, android, etc.) |
| `toggle_debug_paint` | `enable` (bool) | Widget boundary overlay |
| `toggle_repaint_rainbow` | `enable` (bool) | Rotating color overlay on repaint |
| `toggle_slow_animations` | `timeDilation` (double) | Slow down (5.0) or restore (1.0) animations |
| `toggle_performance_overlay` | `enable` (bool) | Real-time frame timing graphs |
| `track_rebuilds` | `enable` (bool) | Widget rebuild counts in inspector overlay |
| `track_repaints` | `enable` (bool) | Repaint region highlighting |

---

## Selectors

Target widgets with any of these formats (tried in order):

| Format | Example | Best for |
|---|---|---|
| `semantics:Label` | `semantics:Submit` | Stable across rebuilds, accessibility-aligned |
| `key:value` | `key:submit_btn` | Widgets with explicit `Key` |
| `text:Content` | `text:Submit` | Visible text content |
| `index:Type:N` | `index:ElevatedButton:0` | Last resort — fragile, use with caution |

Ambiguous matches return an explicit error — the server never silently picks one.

---

## How It Works

```
Flutter App (debug mode)
  └── VM Service WebSocket (ws://127.0.0.1:PORT/TOKEN=/ws)
        └── flutter-devtools-mcp (Dart native binary)
              └── stdio JSON-RPC 2.0
                    └── AI Agent / MCP Client
```

| Capability | Mechanism |
|---|---|
| **Read widget tree** | `ext.flutter.inspector.*` VM Service extensions |
| **Interact (tap, scroll)** | `evaluate()` → `WidgetsBinding.handlePointerEvent()` |
| **Type text** | `evaluate()` → `TextEditingController.text = ...` |
| **Screenshots** | `_flutter.screenshot` extension → PNG |
| **Hot reload** | `reloadSources()` VM Service API |
| **Connect** | `vmServiceConnectUri()` WebSocket handshake |

### Security

- Only localhost (`127.0.0.1`, `localhost`, `::1`) VM Service URLs are accepted
- Auth tokens in URLs are masked in all log output
- The managed `flutter run` process is killed on disconnect

---

## Development

```bash
# Run unit tests
dart test

# Run integration tests (requires running test fixture app)
export FLUTTER_VM_SERVICE_URL=ws://127.0.0.1:<port>/ws
dart test --tags integration

# Static analysis
dart analyze lib/ bin/ --fatal-infos

# Format code
dart format .

# Build native binary
dart compile exe bin/server.dart -o bin/flutter_devtools_mcp_server
```

See [doc/ARCHITECTURE.md](doc/ARCHITECTURE.md) for internals,
[doc/DESIGN_DECISIONS.md](doc/DESIGN_DECISIONS.md) for v1 design rationale.

## License

MIT — see [LICENSE](LICENSE) for details.
