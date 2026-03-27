# Testing Strategy

## Philosophy

Test against ugly real apps, not clean demos. If it works on a messy production app, it works anywhere.

## Test Matrix

### Must-have test scenarios (Day 5)

| Category | Scenario | Why it breaks things |
|---|---|---|
| **Overlays** | `showModalBottomSheet` over content | Obscures nodes, changes hit-test results |
| **Overlays** | `showDialog` with barrier | Overlay stacking, focus trap |
| **Overlays** | `SnackBar` during action | Transient overlay, auto-dismiss |
| **Navigation** | Nested `Navigator` (e.g., tab + modal) | Multiple widget trees, route confusion |
| **Scrolling** | `ListView.builder` with 1000 items | Lazy children, off-screen nodes |
| **Scrolling** | Nested scrollables (horizontal in vertical) | Ambiguous scroll target |
| **Semantics** | App with zero `Semantics` labels | Forces fallback to Key → Text → Index |
| **Semantics** | Overloaded semantics (same label on 5 buttons) | Ambiguity resolution |
| **Keyboard** | Soft keyboard open on mobile | Viewport reshape, bounds shift |
| **Animation** | Hero animation mid-flight | Unstable bounds, duplicate nodes |
| **Animation** | `AnimatedList` insert/remove | Tree mutation during query |
| **State** | `FutureBuilder` loading → loaded | Node appears asynchronously |
| **Custom** | `CustomPaint` (no semantics, no text, no key) | Unaddressable node |
| **Platform** | Platform channel dialog (permissions) | Native overlay, invisible to Flutter |

### Unit tests

| Module | What to test |
|---|---|
| `selectors.dart` | 4-tier resolution, ambiguity detection, visibility filter |
| `transform.dart` | DiagnosticsNode → JSON (consistent output for known inputs) |
| `retry.dart` | Timeout behavior, actionability checks, retry count |
| `connection.dart` | Connection lifecycle, reconnect, error handling |
| `trace.dart` | Structured log format, before/after screenshot references |

### Integration tests

Run against a live Flutter debug app (test fixture app in `test/fixtures/`):

1. **Snapshot round-trip** — snapshot tool returns valid tree, nodes have IDs
2. **Tap by semantics** — tap a labeled button, verify state change
3. **Type into field** — enter text, read back via inspect
4. **Scroll to item** — scroll ListView, verify target becomes visible
5. **Screenshot capture** — returns valid PNG bytes
6. **Hot reload** — modify source, reload, verify tree changes
7. **Ambiguity error** — query matches 3 nodes, get explicit error

### Test fixture app

A deliberately messy Flutter app (`test/fixtures/test_app/`) that includes:

```
- Nested Navigator (tab bar + modal routes)
- ListView.builder (500 items)
- showModalBottomSheet
- showDialog
- SegmentedButton
- CustomPaint widget
- FutureBuilder (simulated async)
- Some widgets with Keys, some without
- Some widgets with Semantics labels, most without
- Text fields with and without focus
- SwitchListTile, Checkbox, Slider
- Hero animation between routes
```

This is the "if it works here, it works anywhere" app.

## CI Strategy (v2)

- Spin up Flutter app in headless mode
- Connect MCP server
- Run integration test suite
- Capture traces + screenshots on failure
- Compare golden screenshots for regressions

## What NOT to test (v1)

- Performance / latency (premature for v1)
- Multiple simultaneous MCP clients
- Profile mode (debug-only for now)
- Remote VM Service connections (localhost-only by design)
