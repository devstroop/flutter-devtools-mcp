# flutter-devtools-mcp — Agent Guide

MCP server for Flutter UI automation via VM Service extensions.

## Stack

| Layer | Technology |
|-------|------------|
| **MCP protocol** | Dart, stdio JSON-RPC 2.0 |
| **VM Service client** | `package:vm_service` (WebSocket) |
| **Gesture injection** | `evaluate()` → `WidgetsBinding.handlePointerEvent()` |
| **Widget tree** | `ext.flutter.inspector.*` VM Service extensions |

## How It Works

1. A Flutter debug app is running (started by `flutter run --debug` or via the `flutter_run` tool)
2. The server connects to its VM Service URL via WebSocket
3. Tools read widget trees, inject gestures, capture screenshots, etc.
4. All interaction happens through the **single active connection** managed by `CurrentConnection`

## Connection Lifecycle

| Tool | What it does |
|---|---|
| `connect` | Manual: pass `vmServiceUrl` from `flutter run` output |
| `flutter_run` | Auto: starts `flutter run --debug`, captures URL, connects |
| `list_apps` | Show registry of known apps (persists across restarts) |
| `status` | Check if currently connected |
| `disconnect` | Close connection and kill managed `flutter run` process |

### Auto-connect on startup

If the server is started with `--vm-service-url URL`, it auto-connects at startup. Otherwise it attempts to reconnect to previously active registry entries (most recent first), with a 5-second timeout per candidate.

## Tool Categories

### 🔌 Connection

| Tool | What it does |
|---|---|
| `connect` | Connect via VM Service URL |
| `disconnect` | Close connection, kill managed process |
| `status` | Check connection state |
| `list_apps` | Show registry of known apps |
| `flutter_run` | Start and auto-connect |

### 🔍 Inspection

| Tool | What it does |
|---|---|
| `widget_tree` | Full widget tree as JSON (types, labels, keys, bounds, children) |
| `inspect` | Deep properties of one widget node by ID |
| `get_parent_chain` | Ancestor chain from node to root |
| `get_render_tree` | Render object tree as text (layout, constraints) |
| `get_layer_tree` | Compositing layer tree (diagnose saveLayer/opacity) |
| `dump_semantics` | Accessibility/semantics tree |

### 👆 Interaction

| Tool | What it does |
|---|---|
| `tap` | Tap widget by selector |
| `type_text` | Focus field and enter text |
| `scroll` | Scroll in a direction |
| `press_back` | Pop navigator route |
| `screenshot` | Capture PNG image |

### ⚙️ Development

| Tool | What it does |
|---|---|
| `hot_reload` | Apply code changes, preserve state |
| `hot_restart` | Full restart, reset state |
| `evaluate` | Run arbitrary Dart expression |
| `get_errors` | Get Flutter framework errors |
| `get_logs` | Capture stdout/stderr/log() output |
| `get_memory` | Heap and external memory usage |

### 🎨 Theme & Platform

| Tool | What it does |
|---|---|
| `toggle_dark_mode` | Light/dark mode |
| `toggle_platform` | Override target platform (ios, android, etc.) |
| `toggle_debug_paint` | Widget boundary overlay |
| `toggle_repaint_rainbow` | Repaint rainbow overlay |
| `toggle_slow_animations` | Slow down / restore animations |
| `toggle_performance_overlay` | Frame timing graphs |
| `track_rebuilds` | Widget rebuild tracking |
| `track_repaints` | Repaint tracking |

## Recommended Workflows

### 🚀 Quick start a Flutter app

```
1. flutter_run(platform: "macos", workingDirectory: "/path/to/project")
   → Server starts flutter run --debug, captures URL, connects
   → Ready for inspection in ~30-60s

2. widget_tree()
   → See everything on screen

3. tap(selector: "semantics:Submit")
   → Interact with a widget
```

### 🔍 Manual connect (app already running)

```
1. User runs flutter run --debug in terminal
2. User copies the VM Service URL
3. connect(vmServiceUrl: "http://127.0.0.1:54321/abc123=/")
4. widget_tree() → inspect → interact
```

## Selectors

| Format | Example | Priority |
|---|---|---|
| `semantics:Label` | `semantics:Submit` | Best — stable across rebuilds |
| `key:value` | `key:submit_btn` | Good — uses widget keys |
| `text:Content` | `text:Submit` | OK — matches visible text |
| `index:Type:N` | `index:ElevatedButton:0` | Last resort |

Ambiguous matches return an error (never silent pick).

## Architecture

```
Flutter App (debug)
  └── VM Service WebSocket (ws://127.0.0.1:PORT/TOKEN=/ws)
        └── flutter-devtools-mcp (Dart native binary)
              └── stdio JSON-RPC
                    └── AI Agent / MCP Client
```

- **Read**: `ext.flutter.inspector.*` extensions → widget tree → simplify for LLM
- **Act**: `evaluate()` → `WidgetsBinding.handlePointerEvent()` for taps, scrolls, text entry
- **Capture**: `_flutter.screenshot` → base64 PNG
- **Security**: localhost-only VM Service URLs required

## Development

```bash
dart test                          # Run unit tests
dart analyze lib/ bin/             # Static analysis
dart compile exe bin/server.dart   # Build native binary
```

See [doc/ARCHITECTURE.md](doc/ARCHITECTURE.md) for full internals.
