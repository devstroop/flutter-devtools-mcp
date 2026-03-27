# Design Decisions

Decisions locked during architecture phase. Each has rationale and is final for v1.

---

## DD-01: Single package, not two

**Decision:** Ship one package (`flutter_devtools_mcp`), not a core library + adapter split.

**Rationale:** The "programmable library" already exists — it's the VM Service extensions. Wrapping them in our own abstraction adds indirection with zero value until a non-MCP consumer exists.

**When to revisit:** When someone needs the core without MCP (CI pipeline, REST API, VS Code extension).

---

## DD-02: SemanticsNode as primary selector, not widget type

**Decision:** Prefer Semantics labels for node selection. Widget type is informational, not primary identity.

**Rationale:**
- Stable across rebuilds (widget tree churns on every `setState`, semantics tree doesn't)
- Accessibility-aligned (forces good practices)
- Closer to "what user perceives" than implementation details

**Fallback hierarchy:**
1. Semantics label
2. ValueKey / Key
3. Text content
4. Index (escape hatch)

---

## DD-03: No caching across tool calls

**Decision:** Every tool invocation queries fresh data from VM Service. No state carried between calls.

**Rationale:** Stale widget tree / render bounds are the #1 cause of flaky automation. The performance cost over localhost WebSocket is negligible (~2-5ms per query). The debugging cost of stale data is enormous.

**When to revisit:** After v1 is stable and profiling shows caching would meaningfully improve UX.

---

## DD-04: Ambiguity = error, not silent pick

**Decision:** If a selector matches multiple nodes, return an explicit error with match count and details. Never silently resolve to one.

**Rationale:** Silent resolution kills trust and creates invisible flakiness. The LLM (or user) can refine the query. Explicit errors are debuggable.

---

## DD-05: Inspector for reading, evaluate() for acting

**Decision:** `ext.flutter.inspector.*` is the read layer. `evaluate()` with `WidgetsBinding` gesture injection is the action layer.

**Rationale:** Inspector returns detailed tree data. For actions (tap, scroll, text entry), we use `evaluate()` to inject `PointerDownEvent`/`PointerUpEvent` directly via `WidgetsBinding.instance.handlePointerEvent()`. This avoids dependency on the legacy `ext.flutter.driver` protocol and gives us full control over gesture synthesis.

**Pipeline:**
- Resolve node via inspector (`valueId`)
- Get screen bounds via `WidgetInspectorService.instance.toObject()` + `localToGlobal()`
- Inject gestures via `evaluate()` on `WidgetsBinding`

---

## DD-06: Coordinate-based tap (not finder-based) for v1

**Decision:** Actions use screen coordinates derived from render tree bounds. Not driver finders.

**Rationale:** Single pipeline — inspector resolves node, render tree gives bounds, action targets center point. This is more consistent than maintaining two parallel resolution systems (inspector selectors + driver finders).

**Constraint:** Always re-fetch bounds immediately before action. Never use cached coordinates.

---

## DD-07: LLM transform lives in MCP layer, not core

**Decision:** DiagnosticsNode → LLM-friendly JSON transformation is part of the MCP server, not a separate library.

**Rationale:** Different consumers want different representations. An LLM wants compact, semantic JSON. A CLI wants tabular output. A test harness wants typed Dart objects. The transform is a presentation concern, not core logic.

---

## DD-08: Auto-retry model, not idle detection

**Decision:** Retry actions until condition is met or timeout expires. Don't try to detect "Flutter is idle."

**Rationale:** Flutter's frame pipeline + microtask queue + animation controllers make "idle" undefinable. Playwright's success comes from retrying assertions, not detecting DOM idle. Same approach here:
1. Resolve selector
2. Check actionability (visible, hit-testable, in viewport, enabled)
3. Attempt action
4. Retry on failure until timeout

---

## DD-09: Structured traces from v1

**Decision:** Every action produces a structured trace entry from day one.

**Format:**
```json
{
  "action": "tap",
  "target": "Submit",
  "selector": "semantics:Submit",
  "resolvedNode": { "id": "...", "type": "ElevatedButton", "bounds": {...} },
  "retryCount": 0,
  "startTime": 1711540000000,
  "endTime": 1711540000150,
  "result": "success"
}
```

**Rationale:** Without structured traces, debugging MCP sessions becomes "re-run and hope." Before/after screenshots per action are also captured but stored separately (not inline in JSON).

---

## DD-10: Localhost only

**Decision:** Refuse VM Service URLs that aren't `127.0.0.1` or `localhost`.

**Rationale:** VM Service is powerful — evaluate arbitrary Dart, inspect state, hot reload. Exposing this to remote connections would be a security hole. For dev tooling, localhost is the only valid use case. This matches Flutter DevTools' own security model.

---

## DD-11: `getRootWidgetSummaryTree` + `getDetailsSubtree` two-step

**Decision:** Summary tree for navigation/search, detail subtree for enrichment before action.

**Rationale:** `getRootWidgetSummaryTree` is intentionally lossy — it prunes deep details and may lazy-load children. Acting on summary data alone risks missing semantics-relevant info. Always enrich via `getDetailsSubtree(valueId)` before resolving a target node's full properties.

---

## DD-12: evaluate() for gesture injection

**Decision:** Actions use `evaluate()` to inject pointer events via `WidgetsBinding.instance.handlePointerEvent()`. This replaced the original plan to use `ext.flutter.driver`.

**Rationale:** `ext.flutter.driver` is legacy and limited — it provides finder-based actions but not coordinate-based gesture synthesis. Using `evaluate()` gives direct access to the gesture pipeline:
- Tap: `PointerDownEvent` → delay → `PointerUpEvent`
- Scroll: `PointerDownEvent` → `PointerMoveEvent` sequence → `PointerUpEvent`
- Text: `TextEditingController.text = ...` via the focused widget
- Back: `Navigator.pop()`

This approach requires zero app-side code and works with any Flutter debug app. `callDriver()` was removed as unused.
