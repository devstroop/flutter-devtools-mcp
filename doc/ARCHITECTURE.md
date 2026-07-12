# Architecture

## Core Principle

Thin MCP adapter over Flutter's existing VM Service extensions. No reimplementation of Flutter internals.

## Layer Separation

```
┌─────────────────────────────────────┐
│          MCP Protocol Layer          │  ← Tool registration, JSON-RPC
├─────────────────────────────────────┤
│         Transform + Selectors        │  ← DiagnosticsNode → LLM JSON
│                                     │     4-tier selector resolution
├─────────────────────────────────────┤
│           VM Service Client          │  ← WebSocket connection
├─────────────────────────────────────┤
│      Flutter VM Service Extensions   │  ← ext.flutter.inspector.*
│      + evaluate() for actions        │     _flutter.screenshot
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
2. Connect to VM Service WebSocket
3. Discover Flutter isolate (main)
4. Register as client
5. Ready to serve tool calls
6. On each tool call: fresh query → resolve → act → respond
7. On shutdown: close WebSocket
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
