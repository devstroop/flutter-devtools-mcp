# flutter_devtools_mcp

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

That's it. The server auto-discovers your running Flutter app via mDNS. No environment variables needed.

> **Multiple apps running?** Set `FLUTTER_VM_SERVICE_URL` to pin a specific one:
> ```json
> "env": { "FLUTTER_VM_SERVICE_URL": "ws://127.0.0.1:XXXXX/YYYY=/ws" }
> ```

## Usage

1. Start your Flutter app: `flutter run --debug`
2. Open your AI editor — the MCP tools appear automatically
3. Ask the AI to interact with your app

## Tools

| Tool | What it does |
|---|---|
| `snapshot` | Widget tree as LLM-friendly JSON |
| `inspect` | Detailed properties of a widget node |
| `tap` | Tap a widget by selector |
| `type_text` | Type into a text field |
| `scroll` | Scroll in a direction |
| `screenshot` | Capture screen as PNG |
| `hot_reload` | Trigger hot reload |
| `evaluate` | Run a Dart expression |
| `press_back` | Pop the top route |

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
