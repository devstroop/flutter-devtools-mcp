import 'dart:async';
import 'dart:io';

import 'package:flutter_devtools_mcp/src/connection.dart';
import 'package:flutter_devtools_mcp/src/current_connection.dart';
import 'package:flutter_devtools_mcp/src/mcp_transport.dart';

import 'package:flutter_devtools_mcp/src/tools/snapshot.dart';
import 'package:flutter_devtools_mcp/src/tools/inspect.dart';
import 'package:flutter_devtools_mcp/src/tools/tap.dart';
import 'package:flutter_devtools_mcp/src/tools/type_text.dart';
import 'package:flutter_devtools_mcp/src/tools/scroll.dart';
import 'package:flutter_devtools_mcp/src/tools/screenshot.dart';
import 'package:flutter_devtools_mcp/src/tools/hot_reload.dart';
import 'package:flutter_devtools_mcp/src/tools/hot_restart.dart';
import 'package:flutter_devtools_mcp/src/tools/evaluate.dart';
import 'package:flutter_devtools_mcp/src/tools/press_back.dart';
import 'package:flutter_devtools_mcp/src/tools/toggle_dark_mode.dart';
import 'package:flutter_devtools_mcp/src/tools/toggle_platform.dart';
import 'package:flutter_devtools_mcp/src/tools/get_memory.dart';
import 'package:flutter_devtools_mcp/src/tools/dump_semantics.dart';
import 'package:flutter_devtools_mcp/src/tools/get_errors.dart';
import 'package:flutter_devtools_mcp/src/tools/get_logs.dart';
import 'package:flutter_devtools_mcp/src/tools/toggle_debug_paint.dart';
import 'package:flutter_devtools_mcp/src/tools/toggle_repaint_rainbow.dart';
import 'package:flutter_devtools_mcp/src/tools/toggle_slow_animations.dart';
import 'package:flutter_devtools_mcp/src/tools/toggle_performance_overlay.dart';
import 'package:flutter_devtools_mcp/src/tools/get_render_tree.dart';
import 'package:flutter_devtools_mcp/src/tools/get_layer_tree.dart';
import 'package:flutter_devtools_mcp/src/tools/get_parent_chain.dart';
import 'package:flutter_devtools_mcp/src/tools/track_rebuilds.dart';
import 'package:flutter_devtools_mcp/src/tools/track_repaints.dart';
import 'package:flutter_devtools_mcp/src/tools/connect.dart';
import 'package:flutter_devtools_mcp/src/tools/disconnect.dart';
import 'package:flutter_devtools_mcp/src/tools/status.dart';
import 'package:flutter_devtools_mcp/src/tools/list_apps.dart';
import 'package:flutter_devtools_mcp/src/registry.dart';

/// MCP server for Flutter UI automation via DevTools VM Service extensions.
///
/// Usage as MCP server (stdio):
///   flutter_devtools_mcp_server
///
/// Direct mode with auto-connect:
///   flutter_devtools_mcp_server --vm-service-url http://127.0.0.1:PORT/TOKEN=/
///
/// Both --vm-service-url VALUE (space-separated) and
/// --vm-service-url=VALUE (equals-separated) forms are accepted.
void main(List<String> args) async {
  // Load persistent registry so URLs survive server restarts.
  try {
    Registry.instance.load();
  } catch (e) {
    stderr.writeln('[flutter_devtools_mcp] Failed to load registry: $e');
  }

  // Graceful shutdown — mark all connections as inactive before exit.
  // Registry failures are non-fatal — the process must always exit.
  void shutdown() async {
    try {
      await CurrentConnection.disconnect();
    } catch (_) {}
    try {
      Registry.instance.markAllDisconnected();
    } catch (_) {}
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => shutdown());
  if (Platform.isLinux || Platform.isMacOS) {
    ProcessSignal.sigterm.watch().listen((_) => shutdown());
  }

  // Check for --vm-service-url flag: auto-connect at startup, then
  // fall through to stdio MCP mode so tools work immediately.
  // Supports both --vm-service-url=VALUE (equals) and
  // --vm-service-url VALUE (space-separated) forms.
  String? parseVmServiceUrl(List<String> args) {
    const prefix = '--vm-service-url';
    for (var i = 0; i < args.length; i++) {
      if (args[i] == prefix && i + 1 < args.length) {
        return args[i + 1].trim();
      }
      if (args[i].startsWith('$prefix=')) {
        return args[i].substring(prefix.length + 1).trim();
      }
    }
    return null;
  }

  final vmServiceUrlArg = parseVmServiceUrl(args);

  /// Mask the auth token in a VM Service URL for safe logging.
  /// The token is the last path segment (e.g. abc123=/ → ***).
  /// Works with or without a trailing slash.
  String maskVmUrl(String url) {
    return url.replaceFirstMapped(
      RegExp(r'^(.*/)[^/]+(/)?$'),
      (m) => '${m[1]}***${m[2] ?? ''}',
    );
  }

  // Auto-connect: serialize attempts so we never race CurrentConnection.set().
  // Try --vm-service-url first, then registry entries (most recent first).
  // First success wins — subsequent candidates are skipped.
  // Candidates are deduplicated by URL to avoid redundant attempts.
  Future<void> autoConnect() async {
    final seen = <String>{};
    final candidates = <String>[];

    // 1. --vm-service-url flag takes priority
    if (vmServiceUrlArg != null && vmServiceUrlArg.isNotEmpty) {
      seen.add(vmServiceUrlArg);
      candidates.add(vmServiceUrlArg);
    }

    // 2. Previously active registry entries (reversed = most recent first)
    //    Skip URLs already present from --vm-service-url.
    for (final entry in Registry.instance.active.reversed) {
      if (seen.add(entry.vmServiceUrl)) {
        candidates.add(entry.vmServiceUrl);
      }
    }

    // Per-candidate timeout prevents any single connect attempt from hanging
    // forever. If the timeout fires, the candidate is skipped and we move to
    // the next. After all candidates are exhausted, control reaches
    // server.run() with a best-effort connection (or none).
    for (final url in candidates) {
      FlutterConnection? conn;
      final isFromRegistry =
          Registry.instance.entries.any((e) => e.vmServiceUrl == url);
      try {
        conn = FlutterConnection(vmServiceUrl: url);
        // Per-connection timer cancels the WebSocket handshake if it
        // takes too long — genuinely aborts the in-flight connect.
        // Use a flag to prevent the timer from acting after connect
        // completes but before the timer is cancelled (race window).
        var connectCompleted = false;
        final connectTimer = Timer(const Duration(seconds: 5), () {
          if (!connectCompleted) conn?.cancel();
        });
        try {
          await conn.connect();
          connectCompleted = true;
        } finally {
          connectTimer.cancel();
        }
        // Set connection BEFORE registering — if CurrentConnection.set()
        // throws, the registry stays clean (no stale active entry).
        await CurrentConnection.set(conn);
        Registry.instance.register(url);
        conn = null; // Ownership transferred — don't dispose below.
        stderr.writeln(
            '[flutter_devtools_mcp] Auto-connected: ${maskVmUrl(url)}');
        return; // First success wins.
      } catch (e) {
        if (conn != null) {
          try {
            await conn.disconnect();
          } catch (_) {}
        }
        if (isFromRegistry) {
          Registry.instance.markDisconnected(url);
        }
        stderr.writeln(
            '[flutter_devtools_mcp] Auto-connect failed: ${maskVmUrl(url)} — $e');
      }
    }

    if (candidates.isEmpty) {
      stderr.writeln(
          '[flutter_devtools_mcp] No auto-connect candidates. Use the connect tool.');
    } else {
      stderr.writeln(
          '[flutter_devtools_mcp] All auto-connect candidates failed.');
    }
  }

  /// Build the McpServer first so tools are registered — the server
  /// doesn't process requests until .run() is called.
  final server = McpServer(
    name: 'flutter_devtools_mcp',
    version: '1.0.0',
    tools: [
      createConnectTool(),
      createDisconnectTool(),
      createStatusTool(),
      createListAppsTool(),
      createSnapshotTool(),
      createInspectTool(),
      createGetParentChainTool(),
      createGetRenderTreeTool(),
      createGetLayerTreeTool(),
      createDumpSemanticsTool(),
      createTapTool(),
      createTypeTextTool(),
      createScrollTool(),
      createPressBackTool(),
      createScreenshotTool(),
      createHotReloadTool(),
      createHotRestartTool(),
      createEvaluateTool(),
      createGetErrorsTool(),
      createGetLogsTool(),
      createGetMemoryTool(),
      createToggleDarkModeTool(),
      createTogglePlatformTool(),
      createToggleDebugPaintTool(),
      createToggleRepaintRainbowTool(),
      createToggleSlowAnimationsTool(),
      createTogglePerformanceOverlayTool(),
      createTrackRebuildsTool(),
      createTrackRepaintsTool(),
    ],
  );

  // Await auto-connect. Each candidate has its own 5s timeout (see above),
  // so the whole loop can't exceed candidates × 5s. No outstanding
  // operations remain after this returns.
  try {
    await autoConnect();
  } catch (e) {
    stderr.writeln('[flutter_devtools_mcp] Auto-connect error: $e');
  }

  await server.run();
}
