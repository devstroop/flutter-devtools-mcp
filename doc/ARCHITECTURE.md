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
│                                     │     ext.flutter.driver.*
│                                     │     _flutter.screenshot
└─────────────────────────────────────┘
```

### Read Layer — `ext.flutter.inspector.*`

These extensions are registered by the Flutter framework (not DevTools). Any WebSocket client can call them.

| Extension | Purpose | Used by |
|---|---|---|
| `getRootWidgetSummaryTree` | Pruned widget tree (framework noise removed) | `snapshot` tool |
| `getDetailsSubtree` | Deep properties for one node (by `valueId`) | `inspect` tool, selector enrichment |
| `getRootRenderObject` | Full render tree with bounds | Coordinate resolution |
| `getChildren` | Children of a node | Tree traversal |
| `getParentChain` | Ancestor chain for a node | Context resolution |
| `getProperties` | Widget properties by node ID | State reading |
| `getSelectedWidget` | Currently selected widget | Debug integration |
| `setSelectionById` | Select a widget programmatically | DevTools bridge |

### Act Layer — `ext.flutter.driver.*`

Legacy driver extensions, still functional and stable for external automation.

Used for: tap, scroll, enterText, waitFor, requestData.

### Screenshot Layer — `_flutter.screenshot`

Captures the current render tree as PNG bytes.

## Data Flow

### Tool Call: `tap(selector: "semantics:Submit")`

```
1. Resolve selector
   └── getRootWidgetSummaryTree() → find matching node by semantics label
   └── if ambiguous → error with match count + details
   └── if no match → error

2. Get bounds
   └── getRootRenderObject() → find render object for matched node
   └── extract screen-space bounds
   └── compute center point

3. Actionability check
   ├── visible? (not offstage, not zero-size)
   ├── hit-testable? (not obscured by overlay)
   ├── within viewport?
   └── enabled? (not disabled widget)

4. Execute
   └── driver tap at computed coordinates

5. Trace
   └── log { action, selector, resolved_node, bounds, timestamp, result }
```

### Tool Call: `snapshot()`

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
2. **Inspector = truth, driver = execution** — never mix
3. **Single node or error** — ambiguous selectors fail explicitly
4. **Always re-fetch bounds before action** — no stale coordinates
5. **Localhost only** — refuse non-local VM Service URLs
