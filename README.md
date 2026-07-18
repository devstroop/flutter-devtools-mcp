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

## Two Ways to Connect

### 1. 🚀 `flutter_run` — Auto-start and connect (recommended)

If you have the Flutter project on disk, the server can start the app for you:

```
flutter_run(platform: "macos", workingDirectory: "/path/to/your/project")
```

This runs `flutter run --debug`, captures the VM Service URL automatically,
connects to it, and keeps the process alive. When you `disconnect()`, the
`flutter run` process is killed cleanly.

**No copy-pasting URLs.** The server handles the entire lifecycle.

### 2. 🔌 `connect` — Manual (app already running)

1. In your terminal, run your Flutter app in debug mode:
   ```bash
   flutter run --debug
   ```
2. Find the VM Service URL in the output:
   ```
   A Dart VM Service on macOS is available at: http://127.0.0.1:54321/abc123=/
   ```
3. Pass it to the `connect` tool:
   ```
   connect(vmServiceUrl: "http://127.0.0.1:54321/abc123=/")
   ```
4. The server normalises it (`http://` → `ws://`, appends `/ws`) and connects.

---

## Persistent Registry

The server remembers every Flutter app you've connected to in
`~/.flutter_devtools_mcp/registry.json`. Entries survive restarts.

- **`list_apps()`** — Show all known apps with URLs, projects, and connection status
- **Auto-connect on startup** — If you start the server with `--vm-service-url URL`,
  it connects immediately. Otherwise it tries previously active registry entries
  (most recent first, 5-second timeout per candidate)
- **`status()`** — Check current connection state

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

## Recommended Workflows

### 🖼 Inspecting the UI

```
1. widget_tree()
   → Returns every widget on screen: type, labels, keys, bounds, children
   → Pick the nodeId of the widget you want to examine

2. inspect(nodeId: "inspector-0x...")
   → Deep properties, styles, constraints for that one widget

3. get_parent_chain(nodeId: "inspector-0x...")
   → See where the widget sits in the hierarchy
```

### 👆 Interacting with a widget

```
1. widget_tree()
   → Find the target widget's selector (prefer semantics: or key:)

2. tap(selector: "semantics:Submit")
   → Resolves widget → checks visibility → taps center

3. type_text(selector: "semantics:EmailField", text: "hello@example.com")
   → Focuses field → enters text

4. scroll(selector: "semantics:ItemList", direction: "down", amount: 200)

5. press_back()
   → Pops the current route
```

### 🐛 Debugging layout issues

```
1. screenshot()
   → Returns a real image of the screen

2. get_render_tree()
   → Text dump of every RenderBox: size, constraints, paint info

3. get_layer_tree()
   → Compositing layer tree — find excessive saveLayer or opacity layers

4. toggle_debug_paint(enable: true)
   → Shows widget boundaries, padding, and alignment guides
   → screenshot() to capture the overlay

5. toggle_performance_overlay(enable: true)
   → Real-time frame timing graphs
   → screenshot() to capture graphs
```

### ⚡ Hot reload / restart

```
1. hot_reload()
   → Applies code changes, preserves state

2. hot_restart()
   → Full reassemble — resets app state
   → Use after hot_reload if state corruption occurs
```

### 🎨 Theme & platform testing

```
1. toggle_dark_mode(enable: true)
   → screenshot() to verify

2. toggle_platform(platform: "ios")
   → Renders iOS-style widgets (Cupertino)
   → screenshot() to verify

3. toggle_platform(platform: "android")
   → Back to Material Design
```

### 🐞 Finding errors

```
1. get_errors()
   → Returns structured Flutter errors (build errors, flex overflows, etc.)

2. get_logs()
   → Captures recent print(), debugPrint(), and log() output

3. evaluate(expression: "someStateVariable")
   → Inspect any Dart value at runtime
```

### 📊 Performance profiling

```
1. toggle_slow_animations(timeDilation: 5.0)
   → Makes animations 5× slower for visual inspection

2. track_rebuilds(enable: true)
   → Widgets show rebuild counts in the inspector overlay

3. track_repaints(enable: true)
   → Repainting regions are highlighted

4. toggle_repaint_rainbow(enable: true)
   → Rotating color overlay on every repaint — spot over-repainting

5. screenshot()
   → Capture the visual debugging state

6. toggle_slow_animations(timeDilation: 1.0)
   → Restore normal speed
```

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

MIT
