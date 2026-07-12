# Flutter Devtools MCP

An [MCP server](https://modelcontextprotocol.io/) that lets AI agents see and interact with your running Flutter app — tap buttons, type text, scroll, take screenshots, and more.

## Install

**Prerequisites:** [Flutter SDK](https://docs.flutter.dev/get-started/install) (includes Dart)

```bash
git clone https://github.com/user/flutter_devtools_mcp.git
cd flutter_devtools_mcp
zsh install.sh
```

The script compiles a native binary and prints the path. Copy the config it outputs into your editor.

<details>
<summary>Manual install</summary>

```bash
dart pub get
dart compile exe bin/server.dart -o bin/flutter_devtools_mcp_server
```

</details>

## Setup

Add to your editor's MCP config:

**VS Code** (`.vscode/mcp.json`):
```jsonc
{
  "servers": {
    "flutter": {
      "command": "/absolute/path/to/flutter_devtools_mcp/bin/flutter_devtools_mcp_server"
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

That's it. The server auto-discovers your running Flutter app via mDNS on the first tool call. No environment variables needed.

> **Multiple apps running?** Call `connect(vmServiceUrl: "ws://...")` to pin a specific one. Or call `connect()` with no args to re-scan via mDNS.

## Usage

1. Start your Flutter app: `flutter run --debug`
2. Open your AI editor — the MCP tools appear automatically
3. Ask the AI to interact with your app

## Tools

| Tool | What it does |
|---|---|---|
| `connect` | Connect/reconnect to a Flutter app (no args = mDNS, or pass a URL). Use instead of DTD tools. |
| `discover` | Scan for running Flutter debug apps via mDNS |
| `status` | Check connection status + detectable apps |
| `launch` | Launch flutter run as subprocess + auto-connect |
| `launch_status` | Check launched process health + recent logs |
| `stop_app` | Kill launched process + disconnect |
| `widget_tree` | Widget tree as structured JSON (every widget, type, label, key, bounds) |
| `inspect` | Detailed properties of a widget node by ID |
| `get_parent_chain` | Ancestor chain — understand layout context |
| `get_render_tree` | Render object tree as text |
| `get_layer_tree` | Compositing layer tree as text |
| `dump_semantics` | Accessibility/semantics tree |
| `tap` | Tap a widget by selector (semantics:, key:, text:, index:) |
| `type_text` | Focus a text field then enter text |
| `scroll` | Scroll a scrollable widget |
| `screenshot` | Capture screen as PNG image |
| `hot_reload` | Trigger hot reload |
| `hot_restart` | Full hot restart (resets state) |
| `evaluate` | Run a Dart expression |
| `press_back` | Pop the top route |
| `get_errors` | Get Flutter framework errors |
| `get_logs` | Capture stdout/stderr/log() output |
| `get_memory` | Get memory usage (heap, external) |
| `toggle_dark_mode` | Toggle dark/light mode |
| `toggle_platform` | Override target platform |
| `toggle_debug_paint` | Toggle widget boundary overlay |
| `toggle_repaint_rainbow` | Toggle repaint rainbow |
| `toggle_slow_animations` | Slow down/restore animations |
| `toggle_performance_overlay` | Toggle frame timing graphs |
| `track_rebuilds` | Toggle widget rebuild tracking |
| `track_repaints` | Toggle repaint tracking |

### Selectors

Target widgets with these formats (tried in order):

| Format | Example | When to use |
|---|---|---|
| `semantics:Label` | `semantics:Submit` | Best — uses accessibility labels |
| `key:value` | `key:submit_btn` | Good — uses widget keys |
| `text:Content` | `text:Submit` | OK — matches visible text |
| `index:Type:N` | `index:ElevatedButton:0` | Last resort — fragile |

Ambiguous matches return an error — the server never silently picks one.

## How it works

```
Flutter App (debug)  →  VM Service WebSocket  →  This MCP Server  →  AI Agent
```

- **Reads** widget trees via `ext.flutter.inspector.*` extensions
- **Acts** via `evaluate()` gesture injection (tap, type, scroll)
- **Captures** screenshots via `_flutter.screenshot`
- **Discovers** apps via mDNS (`_dartobservatory._tcp`)
- **Connects lazily** — server starts instantly, connects on first tool call

## Development

```bash
# Run tests
dart test

# Run with verbose logging
dart run bin/server.dart --verbose

# Compile after changes
dart compile exe bin/server.dart -o bin/flutter_devtools_mcp_server
```

See [doc/ARCHITECTURE.md](doc/ARCHITECTURE.md) for internals.

## License

MIT
