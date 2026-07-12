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

Run against a live Flutter debug app (test fixture app in `test/fixtures/test_app/`):

1. **Snapshot round-trip** — widget_tree tool returns valid tree, nodes have IDs
2. **Inspect round-trip** — inspect a specific node, get properties
3. **Selector resolution** — resolve by semantics label, key, and text
4. **Tap by semantics** — tap a labeled button, verify state change
5. **Type into field** — enter text, read back via inspect
6. **Scroll** — scroll a list view, verify success
7. **Press back** — pop a route via Navigator
8. **Screenshot capture** — returns valid PNG bytes
9. **Evaluate** — evaluate Dart expression, get result
10. **Hot reload** — trigger hot reload, verify success
11. **Trace log** — verify trace entries are recorded

#### Running integration tests

```bash
# 1. Start the test fixture app
cd test/fixtures/test_app
flutter run --debug --disable-service-auth-codes

# 2. Note the VM Service URL from output

# 3. In another terminal, run integration tests
export FLUTTER_VM_SERVICE_URL=ws://127.0.0.1:XXXXX/ws
dart test --tags integration
```

### Test fixture app

The test fixture at `test/fixtures/test_app/` is a 3-tab Flutter app:

- **Widget Gallery** — ElevatedButton, TextField, CheckboxListTile, Switch, Slider, DropdownButton (with semantics labels and keys)
- **Scroll Tests** — ListView.builder with 100 numbered items
- **Form Tests** — Multiple TextFields with different labels

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
