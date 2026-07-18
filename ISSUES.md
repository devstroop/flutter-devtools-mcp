# flutter-devtools-mcp — Known Issues & Technical Debt

---

## ✅ Resolved

| # | Issue | Fix | Date |
|---|---|---|---|
| TD3 | **TraceLog abstraction removed** — `trace.dart` + structured tracing was dead weight (produced data no tool consumed). Replaced with direct `_log.fine()` calls in error paths. 22 tool files cleaned up. | [`trace.dart` deleted, all imports + calls removed] | 2026-07-18 |
| R1 | **get_errors simplified** — Removed event stream subscription, 300ms heuristic, `streamListen('Extension')`, and `FlutterError.resetErrorCount()` evaluate call. Now just calls `ext.flutter.inspector.getErrorInfo` directly. | [`lib/src/tools/get_errors.dart` rewritten] | 2026-07-18 |
| R2 | **TraceLog test group removed** from integration tests. | [`test/integration_test.dart` cleaned up] | 2026-07-18 |
| R3 | **Agent aliases added** — New agents try `launch` or `run_app` instead of `flutter_run`, causing stalls. Now all three names are registered as aliases sharing the same handler. | [`flutter_run.dart` + `server.dart`] | 2026-07-18 |

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
