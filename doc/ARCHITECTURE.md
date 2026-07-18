# Architecture

## Core Principle

Thin MCP adapter over Flutter's existing VM Service extensions. No reimplementation of Flutter internals.

## Layer Separation

```
┌─────────────────────────────────────┐
│          MCP Protocol Layer         │  ← Tool registration, JSON-RPC
├─────────────────────────────────────┤
│         Transform + Selectors       │  ← DiagnosticsNode → LLM JSON
│                                     │     4-tier selector resolution
├─────────────────────────────────────┤
│           VM Service Client         │  ← WebSocket connection
├─────────────────────────────────────┤
│      Flutter VM Service Extensions  │  ← ext.flutter.inspector.*
│      + evaluate() for actions       │     _flutter.screenshot
└─────────────────────────────────────┘
```

### Read Layer — `ext.flutter.inspector.*`

These extensions are registered by the Flutter framework (not DevTools). Any WebSocket client can call them.

| Extension | Purpose | Used by |
|---|---|---|
| `getRootWidgetSummaryTree` | Pruned widget tree (framework noise removed) | `widget_tree` tool |
| `getDetailsSubtree` | Deep properties for one node (by `valueId`) | `inspect` tool, selector enrichment |
| `getRootRenderObject` | Full render tree with bounds | Coordinate resolution |
| `getChildren` | Children of a node | Tree traversal |
| `getParentChain` | Ancestor chain for a node | Context resolution |
| `getProperties` | Widget properties by node ID | State reading |
| `getSelectedWidget` | Currently selected widget | Debug integration |
| `setSelectionById` | Select a widget programmatically | DevTools bridge |

### Connection Management

The server maintains a **single active connection** via `CurrentConnection` singleton.
A **persistent registry** (`~/.flutter_devtools_mcp/registry.json`) saves known VM Service URLs.

| Tool | Mechanism |
|---|---|
| `connect` | `vmServiceConnectUri()` WebSocket handshake → isolate discovery → root library resolution |
| `disconnect` | `_service.dispose()` + `ManagedFlutterRun.kill()` |
| `flutter_run` | `Process.start('flutter run --debug')` → stdout/stderr capture (regex) → `connect()` |
| `list_apps` | Reads registry file, returns all entries with connection status |
| `status` | Checks `CurrentConnection.isConnected` |

#### ManagedFlutterRun

The `flutter_run` tool spawns a child `flutter run --debug` process:

1. Resolves the Flutter binary (PATH → `which` → platform fallback paths)
2. `Process.start()` runs `flutter run -d <platform> --debug`
3. Both stdout and stderr are forwarded to the server's stderr
4. Regex `A Dart VM Service.*is available at: (http://\S+)` captures the URL
5. Once captured, `FlutterConnection.connect()` is called
6. The process stays alive; `kill()` sends `SIGTERM` → 3s grace → `SIGKILL`
7. PID guard prevents stale exit handlers from affecting a new process

#### Auto-connect on Startup

`--vm-service-url URL` flag auto-connects at startup. Without the flag, the server
tries previously active registry entries (most recent first, 5s timeout per candidate).
Candidates are deduplicated. Registry registration is best-effort.

### Act Layer — `evaluate()` gesture injection

Actions are performed by evaluating Dart expressions directly in the running app
via the VM Service `evaluate()` API. This bypasses the legacy Flutter Driver protocol entirely.

- **Tap / scroll**: `WidgetsBinding.instance.handlePointerEvent()` with synthetic pointer events
- **Text entry**: `TextEditingController.text =` on the focused field's controller
- **Back navigation**: `Navigator.of(context).maybePop()`
- **Bounds resolution**: `WidgetInspectorService.instance.toObject()` → Element → RenderBox → `localToGlobal`

### Screenshot Layer — `_flutter.screenshot`

Captures the current render tree as PNG bytes.

## Data Flow

### Tool Call: `tap(selector: "semantics:Submit")`

```
1. Resolve selector
   └── getRootWidgetSummaryTree() → flatten tree → match by semantics label
   └── if ambiguous → error with match count + details
   └── if no match → error

2. Get bounds
   └── evaluate() → WidgetInspectorService.toObject(id, group)
   └── access Element → RenderBox → localToGlobal(Offset.zero) + size
   └── compute center point

3. Actionability check
   ├── visible? (not offstage, not zero-size)
   ├── hit-testable? (always true in v1 — v2: RenderView.hitTest)
   ├── within viewport?
   └── enabled? (check onPressed != null via evaluate)

4. Execute
   └── evaluate() → handlePointerEvent(PointerDownEvent + PointerUpEvent at center)

5. Trace
   └── log { action, selector, resolved_node, bounds, timestamp, result }
```

### Tool Call: `widget_tree()` (formerly `snapshot()`)

```
1. getRootWidgetSummaryTree()
2. For each node: transform DiagnosticsNode → LLM-friendly JSON
3. Return pruned tree
```

## Node Representation

The core abstraction is a **semantic node**: a widget-tree node enriched with render information.

```json
{
  "id": "inspector-0x12345",
  "type": "ElevatedButton",
  "label": "Submit",
  "key": "submit_btn",
  "bounds": { "x": 120, "y": 540, "w": 200, "h": 48 },
  "visible": true,
  "enabled": true,
  "inScrollable": false,
  "children": []
}
```

Source data:
- `type` — from `DiagnosticsNode.description`
- `label` — from semantics label (if available)
- `key` — from `ValueKey` or `Key` (if available)
- `bounds` — from `RenderObject` paintBounds + transform
- `visible` — derived from offstage + size + opacity
- `enabled` — from widget state (e.g., `onPressed != null`)
- `inScrollable` — from ancestor check (is parent a `RenderSliver`?)

## Connection Lifecycle

```
1. MCP server starts
2. Load persistent registry from disk
3. Auto-connect (if `--vm-service-url` flag or active registry entries exist)
4. Listen for MCP tool calls via stdin JSON-RPC
5. On `connect` / `flutter_run`:
   a. Connect to VM Service WebSocket
   b. Discover Flutter isolate (main)
   c. Register in CurrentConnection singleton
   d. Persist URL to registry
6. On each tool call: fresh query → resolve → act → respond
7. On `disconnect`:
   a. Mark URL as disconnected in registry
   b. Close WebSocket (`_service.dispose()`)
   c. Kill managed flutter run process (if any)
8. On process exit (`SIGINT`/`SIGTERM`): mark all registry entries inactive, exit
```

## Constraints

1. **No caching across tool calls** — every invocation starts fresh
2. **Inspector = truth, evaluate = execution** — read via extensions, act via evaluate
3. **Single node or error** — ambiguous selectors fail explicitly
4. **Always re-fetch bounds before action** — no stale coordinates
5. **Localhost only** — refuse non-local VM Service URLs

## Development Setup

### Prerequisites

- Dart SDK ≥ 3.0
- Flutter SDK (for running the test fixture app)
- A physical or virtual device / emulator

### Running the test fixture

```bash
cd test/fixtures/test_app
flutter run --debug --disable-service-auth-codes
# Note the VM Service URL
```

### Running tests

```bash
# Unit tests only
dart test --exclude-tags integration

# Integration tests (requires running test fixture)
export FLUTTER_VM_SERVICE_URL=ws://127.0.0.1:<port>/ws
dart test --tags integration

# All tests
dart test
```

### Static analysis

```bash
dart analyze lib/ bin/server.dart
```
