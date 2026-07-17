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

## Usage

The workflow is simple:

1. **Run your app**: `flutter run --debug` (or `flutter run -d macos --debug`, etc.)
2. **Copy the VM Service URL** from the output (looks like `http://127.0.0.1:54321/abc123=/`)
3. **Call `connect`**: `connect(vmServiceUrl: "http://127.0.0.1:54321/abc123=/")`
4. **Interact**: call `widget_tree`, `tap`, `type_text`, `screenshot`, etc.
5. **Done?** Call `disconnect()` to close the WebSocket.

---

## Recommended Workflows

These are battle-tested sequences optimized for AI agents. Follow them step by step.

### 🔍 Inspecting the UI

```
1. connect(vmServiceUrl: "...")
   → Wait for {"status":"connected"}

2. widget_tree()
   → Returns every widget on screen: types, labels, keys, bounds, children
   → Pick the nodeId of the widget you want to examine

3. inspect(nodeId: "inspector-0x...")
   → Deep properties, styles, constraints for that one widget

4. get_parent_chain(nodeId: "inspector-0x...")
   → See where the widget sits in the hierarchy (child → root)
```

### 👆 Interacting with a widget

```
1. widget_tree()
   → Find the target widget's selector (semantics:Label is best)

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
   → Returns a real image of the screen (base64 PNG, rendered as image by MCP)

2. get_render_tree()
   → Text dump of every RenderBox: size, constraints, paint info

3. get_layer_tree()
   → Compositing layer tree — find excessive saveLayer or opacity layers

4. toggle_debug_paint(enable: true)
   → Shows widget boundaries, padding, and alignment guides
   → screenshot() to capture the overlay

5. toggle_performance_overlay(enable: true)
   → Real-time frame timing graphs (UI + raster thread)
   → screenshot() to capture graphs for analysis
```

### ⚡ Hot reload / restart cycle

```
1. hot_reload()
   → Applies code changes, preserves state
   → Wait for {"status":"success"}

2. hot_restart()
   → Full reassemble — resets app state
   → Use after hot_reload if state corruption occurs
```

### 🎨 Theme & platform testing

```
1. toggle_dark_mode(enable: true)
   → Switches to dark mode
   → screenshot() to verify

2. toggle_dark_mode(enable: false)
   → Back to light mode

3. toggle_platform(platform: "ios")
   → Renders iOS-style widgets (Cupertino)
   → screenshot() to verify

4. toggle_platform(platform: "android")
   → Back to Material Design
```

### 🐞 Finding errors

```
1. get_errors()
   → Returns structured Flutter errors (build errors, render flex overflows, etc.)

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

7. track_rebuilds(enable: false)
   → Disable tracking
```

## Tools

| Tool | What it does |
|---|---|
| `connect` | Connect to a running Flutter debug app (requires vmServiceUrl from flutter run output) |
| `disconnect` | Disconnect from the current app |
| `status` | Check whether connected to a Flutter app |
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
- **Connects on demand** — pass the VM Service URL to `connect`, then all tools use that single connection

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
