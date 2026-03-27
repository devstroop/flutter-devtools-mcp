# flutter_devtools_mcp

MCP server for Flutter UI automation. Thin adapter over Flutter's existing VM Service extensions — no framework reimplementation.

## What this is

A [Model Context Protocol](https://modelcontextprotocol.io/) server that connects to a running Flutter debug app and exposes widget inspection, interaction, and screenshot tools. Built on top of the same `ext.flutter.inspector.*` and `ext.flutter.driver.*` extensions that Flutter DevTools uses.

```
Flutter App (debug mode)
    │
    ├── ext.flutter.inspector.*   ← tree reading
    ├── ext.flutter.driver.*      ← actions (tap, type, scroll)
    └── _flutter.screenshot       ← capture
    │
    ▼
VM Service WebSocket (ws://127.0.0.1:<port>/ws)
    │
    ▼
flutter_devtools_mcp (this server)
    │
    ▼
LLM / CLI / Automation Client
```

## MCP Tools

| Tool | Description |
|---|---|
| `snapshot` | Get pruned widget tree (LLM-friendly JSON) |
| `inspect` | Get detailed properties of a specific node |
| `tap` | Tap a widget by selector |
| `type_text` | Enter text into a focused field |
| `scroll` | Scroll a scrollable widget |
| `screenshot` | Capture current screen as PNG |
| `hot_reload` | Trigger hot reload |
| `evaluate` | Evaluate a Dart expression at runtime |

## Selector System

Widgets are targeted using a 4-tier fallback:

1. **Semantics label** (primary, recommended) — `semantics:Submit`
2. **Key** (fallback) — `key:submit_btn`
3. **Text content** (last resort) — `text:Submit`
4. **Index** (escape hatch, unstable) — `index:Button:3`

Rules:
- Exact match > partial match
- Visible nodes only (by default)
- Ambiguous matches return an explicit error (never silently pick one)
- Selector resolution feedback: warns when falling back from semantics

## Quick Start

### 1. Start your Flutter app in debug mode

```bash
flutter run --debug
# Note the VM Service URL: ws://127.0.0.1:XXXXX/YYYY=/ws
```

### 2. Run the MCP server

```bash
dart run bin/server.dart --vm-service-url ws://127.0.0.1:XXXXX/YYYY=/ws
```

### 3. Configure in your MCP client

```json
{
  "mcpServers": {
    "flutter": {
      "command": "dart",
      "args": ["run", "/path/to/flutter_devtools_mcp/bin/server.dart"],
      "env": {
        "FLUTTER_VM_SERVICE_URL": "ws://127.0.0.1:XXXXX/YYYY=/ws"
      }
    }
  }
}
```

## How It Works

**Read layer** — `ext.flutter.inspector.*`
- `getRootWidgetSummaryTree` → pruned widget tree (framework internals removed)
- `getDetailsSubtree` → deep properties for a specific node
- `getRootRenderObject` → render tree with bounds

**Act layer** — `ext.flutter.driver.*`
- Tap, scroll, enter text via coordinate-based or finder-based targeting
- Actions always re-fetch bounds before execution (no stale coordinates)

**Key constraint: No caching across tool calls.** Every tool invocation starts with fresh data from the VM Service. This prevents stale-state bugs at the cost of negligible latency over localhost WebSocket.

## Requirements

- Dart SDK ≥ 3.0
- A Flutter app running in debug or profile mode
- `package:vm_service` for VM Service protocol communication

## Project Structure

```
flutter_devtools_mcp/
├── bin/
│   └── server.dart             ← entry point
├── lib/
│   ├── flutter_devtools_mcp.dart  ← barrel export
│   └── src/
│       ├── connection.dart     ← VM Service WebSocket client
│       ├── selectors.dart      ← 4-tier selector resolution
│       ├── transform.dart      ← DiagnosticsNode → LLM-friendly JSON
│       ├── actions.dart        ← coordinate-based tap/scroll/type
│       ├── retry.dart          ← auto-retry with actionability checks
│       ├── trace.dart          ← structured action logging
│       └── tools/
│           ├── snapshot.dart   ← widget tree snapshot tool
│           ├── inspect.dart    ← node detail tool
│           ├── tap.dart        ← tap tool
│           ├── type_text.dart  ← text entry tool
│           ├── scroll.dart     ← scroll tool
│           ├── screenshot.dart ← screenshot tool
│           ├── hot_reload.dart ← hot reload tool
│           └── evaluate.dart   ← Dart evaluation tool
├── test/
├── doc/
│   ├── ARCHITECTURE.md
│   ├── DESIGN_DECISIONS.md
│   └── TESTING.md
├── pubspec.yaml
├── analysis_options.yaml
└── README.md
```

## License

MIT
