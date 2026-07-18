# flutter-devtools-mcp — Known Issues & Technical Debt

---

## ✅ Resolved

| # | Issue | Fix | Date |
|---|---|---|---|
| TD3 | **TraceLog abstraction removed** — `trace.dart` + structured tracing was dead weight (produced data no tool consumed). Replaced with direct `_log.fine()` calls in error paths. 22 tool files cleaned up. | [`trace.dart` deleted, all imports + calls removed] | 2026-07-18 |
| R1 | **get_errors simplified** — Removed event stream subscription, 300ms heuristic, `streamListen('Extension')`, and `FlutterError.resetErrorCount()` evaluate call. Now just calls `ext.flutter.inspector.getErrorInfo` directly. | [`lib/src/tools/get_errors.dart` rewritten] | 2026-07-18 |
| R2 | **TraceLog test group removed** from integration tests. | [`test/integration_test.dart` cleaned up] | 2026-07-18 |
| R3 | **Agent aliases added** — New agents try `launch` or `run_app` instead of `flutter_run`, causing stalls. Now all three names are registered as aliases sharing the same handler. | [`flutter_run.dart` + `server.dart`] | 2026-07-18 |
| R4 | **`connect` → `attach` renamed** with `connect` as alias. `launch` → primary, with `run` + `flutter_run` as aliases. | [`connect.dart` refactored, `flutter_run.dart` primary changed] | 2026-07-18 |

---

## 🔴 Bugs Found via MCP Testing (WorxVPN audit session)

_These were discovered during a live MCP debugging session against WorxVPN on 2026-07-18._

### B1. `screenshot` response format prevents reliable parsing

When `_mcp_content_type: 'image'` is set, `mcp_transport.dart` wraps the response
as `content: [{type: 'image', data: '...', mimeType: 'image/png'}]`. When the flag
is NOT set, the response is `content: [{type: 'text', text: '{"data":"...",...}'}]`.
Tools that call `screenshotImpl` and expect to set `_mcp_content_type` may miss it,
causing inconsistent response shapes across different callers.

**Found in**: Manual testing with WorxVPN — had to try 3 different parsing paths
to extract base64 PNG data from the response.

**Fix**: Ensure all `screenshot` callers set `result['_mcp_content_type'] = 'image'`
before returning, or move the flag into `screenshotImpl` itself.

**Files**: `lib/src/tools/screenshot.dart`, `lib/src/mcp_transport.dart:136-146`

**Priority**: 🔴 High — breaks programmatic screenshot consumers.

---

### B2. `text:Connect` ambiguous — 2 matches blocks navigation

WorxVPN's NavigationRail has a "Connect" nav item, and ConnectionScreen has HTML-like
text "Connect" in its content. Selecting `text:Connect` always fails with
`SelectorError: Ambiguous: 2 nodes match`. The agent cannot navigate back to the
Connection tab without guessing `index:Text:0` or `index:Text:1`.

**Found in**: Testing nav flow — `text:Connect` Error while `text:Log` continued.

**Fix**: Add context-aware selector priority: prefer NavigationRail destinations
over body content, or detect ambiguous navigation matches and hint at index-based
selectors in the error message.

**Files**: `lib/src/selectors.dart`

**Priority**: 🟡 Medium — workaround exists (index:Text:N) but breaks agent flows.

---

### B3. Tap actionability check timeouts on deep trees

`tap(text:Log)` returned `TimeoutException after 0:00:05.000000: tap(text:Log)
failed after 41 attempts`, yet the Log screen **did load** — the tap was injected
successfully. The failure is in `checkActionability` or `getBounds` where the
retry loop expires before the screen transition completes.

**Found in**: Navigating between WorxVPN screens — every text-selector tap on
nav items timed out, but the screen change was confirmed by subsequent `widget_tree`.

**Fix**: Reduce retry complexity for taps that don't need bounds confirmation,
or increase default timeout for `withRetry` on text selector taps.

**Files**: `lib/src/retry.dart`, `lib/src/tools/tap.dart`, `lib/src/actions.dart`

**Priority**: 🟡 Medium — causes false errors; actual gesture succeeds.

---

### B4. `get_errors` crashes on release-mode Flutter apps

Release-mode Flutter apps (including WorxVPN compiled with `--release` or
`flutter build macos --release`) don't support `ext.flutter.inspector.getErrorInfo`.
The tool returns raw error: `"ext.flutter.inspector.getErrorInfo: (-32601) Unknown method"`.

**Found in**: Testing `get_errors` on WorxVPN release build — always returns error.

**Fix**: Catch `-32601` / "Unknown method" response and return a graceful message:
`"errors not available in this build mode (debug mode required)"`.

**Files**: `lib/src/tools/get_errors.dart`

**Priority**: 🟡 Medium — tool breaks in release mode; expected to work by agents.

---

### B5. Response envelope inconsistency across tools

| Tool | Content format |
|---|---|
| `widget_tree` | `content[0].text` → JSON → direct tree data |
| `get_render_tree` | `content[0].text` → JSON → `content[0].text` → nested data |
| `screenshot` (no image flag) | `content[0].text` → JSON → `data` field |
| `screenshot` (with image flag) | `content[0]` has `type: 'image'` + `data` |
| `get_memory` | `content[0].text` → direct JSON |

**Found in**: Writing Python parser — had to add per-tool unwrapping logic.

**Fix**: Standardise: all tools should return direct JSON in `content[0].text`
(no nested content wrapper). The double-wrapping comes from `McpServer.handleToolCall`
in `mcp_transport.dart` which wraps `text: json.encode(result)` — and some tools
return `{'content': [...]}` instead of the result map.

**Files**: `lib/src/mcp_transport.dart:125-165`

**Priority**: 🟢 Low — cosmetic but increases integration complexity.

---

## 🟡 Technical Debt

### TD1. `connect` tool should be named `attach`

The MCP tool for connecting to a running Flutter app is currently named `connect`.
The Flutter ecosystem standard is `flutter attach` (the CLI command for connecting
to an already-running debug instance). Renaming to `attach` would:

- Align with Flutter's own terminology
- Create a clearer semantic pair: `flutter_run` (start new) vs `attach` (connect existing)
- Make the tool name more intuitive for Flutter developers

**Impact:** Breaking change for any agent workflows or configs that reference `connect`.
Requires updating:
- `lib/src/tools/connect.dart` — filename and `createConnectTool()` function
- `bin/server.dart` — import and tool registration
- `README.md`, `AGENTS.md`, `server.json`, `doc/ARCHITECTURE.md` — documentation
- `.vscode/mcp.json` — if any tool references use the name

**Priority:** Low — functional but inconsistent.

---

### TD2. `list_apps` returns entire registry as raw JSON

The `list_apps` tool serializes all `RegistryEntry` objects directly to JSON
without filtering or pagination. For a registry with hundreds of entries, this
could produce very large responses.

**Fix:** Add optional `activeOnly` filter and/or `limit` pagination parameter.

**Priority:** Low — registry is small in practice.

---

### TD3. No unit tests for registry, current_connection, list_apps, flutter_run

| Module | Lines of logic | Test coverage |
|---|---|---|
| `lib/src/registry.dart` | ~130 (load, save, register, markDisconnected, markAllDisconnected) | ❌ |
| `lib/src/current_connection.dart` | ~80 (set, get, disconnect lifecycle, reconnection) | ❌ |
| `lib/src/managed_run.dart` | ~120 (process start, kill, binary resolution, exit handler) | ❌ |
| `lib/src/tools/list_apps.dart` | ~30 (handler, toToolResult serialization) | ❌ |
| `lib/src/tools/flutter_run.dart` | ~50 (handler, error handling) | ❌ |

**Risk:** These are correctness-critical paths (connection lifecycle, process
management) with zero automated regression coverage.

**Priority:** Medium — should be addressed before v1.1.

---

### TD4. Token leaked in `connection.dart` log if logging level is lowered

The `Connection` logger in `lib/src/connection.dart` writes `_log.info('Connecting to ${maskUrlToken(vmServiceUrl)}')` with a masked URL.
However, `maskUrlToken` returns the raw URL if `Uri.tryParse` fails (edge case).
All other `_log.fine()` calls in the same file use unmasked URLs.

**Fix:** Ensure all log entries covering VM Service URLs go through `maskUrlToken`.

**Priority:** Low — `FINE` level logs are filtered out by the root handler.
