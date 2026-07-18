# Contributing

Thank you for considering contributing to `flutter-devtools-mcp`.

## Project Overview

`flutter-devtools-mcp` is an [MCP server](https://modelcontextprotocol.io/)
that lets AI agents see and interact with running Flutter apps. It talks to
the Flutter VM Service via WebSocket and exposes tool calls over stdio JSON-RPC.

### Stack

| Layer | Technology |
|-------|------------|
| **MCP protocol** | Dart, stdio JSON-RPC 2.0 |
| **VM Service client** | `package:vm_service` (WebSocket) |
| **Gesture injection** | `evaluate()` → `WidgetsBinding.handlePointerEvent()` |
| **Widget tree** | `ext.flutter.inspector.*` VM Service extensions |
| **Build** | `dart compile exe` → native binary |

### Repository Layout

```
flutter-devtools-mcp/
├── bin/
│   ├── server.dart            ← Entry point, tool registration, main()
│   └── flutter_devtools_mcp_server   ← Compiled binary (gitignored)
│
├── lib/
│   ├── src/
│   │   ├── connection.dart         ← WebSocket + isolate management
│   │   ├── current_connection.dart ← Singleton active connection
│   │   ├── managed_run.dart        ← flutter run process lifecycle
│   │   ├── registry.dart           ← Persistent URL registry
│   │   ├── mcp_transport.dart      ← JSON-RPC stdio server
│   │   ├── selectors.dart          ← 4-tier selector resolution
│   │   ├── actions.dart            ← Gesture injection + bounds
│   │   ├── retry.dart              ← Action retry with timeout
│   │   └── tools/                  ← One file per MCP tool
│   │       ├── connect.dart / disconnect.dart / status.dart
│   │       ├── launch.dart (aliases: run, flutter_run)
│   │       ├── attach.dart (alias: connect)
│   │       ├── tap.dart / type_text.dart / scroll.dart
│   │       ├── screenshot.dart / hot_reload.dart / evaluate.dart
│   │       ├── widget_tree.dart / inspect.dart
│   │       ├── toggle_*.dart (8 theme/debug toggles)
│   │       ├── track_*.dart (2 tracking tools)
│   │       └── list_devices.dart / list_apps.dart
│   └── flutter_devtools_mcp.dart  ← Public library exports
│
├── test/                        ← Unit + integration tests
├── doc/                         ← Architecture, design decisions, testing
├── .github/
│   ├── workflows/               ← CI (lint, test, release)
│   └── PULL_REQUEST_TEMPLATE.md
│
├── README.md, AGENTS.md, ISSUES.md, CHANGELOG.md
└── pubspec.yaml
```

## Development Setup

### Prerequisites

- **Dart SDK** ≥ 3.0 (`dart --version`)
- **Flutter SDK** (for running the test fixture app)
- A physical or virtual Flutter device

### Quick Start

```bash
dart pub get
dart compile exe bin/server.dart -o bin/flutter_devtools_mcp_server
dart test
```

### Code Style

- Follow the existing patterns in `lib/src/tools/` — each tool has two parts:
  1. An `Impl` function (pure logic, returns `Map<String, Object?>`)
  2. A `create*Tool()` factory (schema + handler)
- Use `package:logging` (`_log.info` / `_log.warning`) for observability
- `dart format .` before committing

### Static Analysis

```bash
dart analyze lib/ bin/ --fatal-infos
```

Zero issues required before merging.

### Testing

```bash
# Unit tests (no Flutter app needed)
dart test --exclude-tags integration

# Integration tests (requires running test fixture app)
export FLUTTER_VM_SERVICE_URL=ws://127.0.0.1:<port>/ws
dart test --tags integration

# All tests
dart test
```

See [doc/TESTING.md](doc/TESTING.md) for the full testing strategy.

## Pull Request Process

1. Create a branch from `main`
2. Make your changes with clear commit messages
3. Run `dart analyze lib/ bin/ --fatal-infos` — zero issues
4. Run `dart test --exclude-tags integration` — all pass
5. Update `AGENTS.md` if tool names or behaviour changed
6. Update `ISSUES.md` if fixing a known issue or adding debt
7. Open a PR using the template — include before/after if visual

## Code of Conduct

Be respectful. This is an open-source project. All contributions are welcome
regardless of experience level.

## License

MIT — see [LICENSE](LICENSE).
