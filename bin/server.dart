import 'dart:io';

import 'package:flutter_devtools_mcp/src/mcp_transport.dart';
import 'package:flutter_devtools_mcp/src/current_connection.dart';

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

/// MCP server for Flutter UI automation via DevTools VM Service extensions.
///
/// Zero-config stdio server. Connect to a running Flutter debug app by
/// passing its VM Service URL to the connect tool.
///
/// Build: dart compile exe bin/server.dart -o bin/flutter_devtools_mcp_server
void main() {
  // Graceful shutdown — disconnect and exit
  ProcessSignal.sigint.watch().listen((_) async {
    await CurrentConnection.disconnect();
    exit(0);
  });
  // SIGTERM is POSIX-only — skip on Windows where it throws SignalException
  if (Platform.isLinux || Platform.isMacOS) {
    ProcessSignal.sigterm.watch().listen((_) async {
      await CurrentConnection.disconnect();
      exit(0);
    });
  }

  McpServer(
    name: 'flutter_devtools_mcp',
    version: '1.0.0',
    tools: [
      // Connection management
      createConnectTool(),
      createDisconnectTool(),
      createStatusTool(),

      // Inspection
      createSnapshotTool(),
      createInspectTool(),
      createGetParentChainTool(),
      createGetRenderTreeTool(),
      createGetLayerTreeTool(),
      createDumpSemanticsTool(),

      // Interaction
      createTapTool(),
      createTypeTextTool(),
      createScrollTool(),
      createPressBackTool(),
      createScreenshotTool(),

      // Flutter lifecycle
      createHotReloadTool(),
      createHotRestartTool(),
      createEvaluateTool(),
      createGetErrorsTool(),
      createGetLogsTool(),
      createGetMemoryTool(),

      // Overlay toggles
      createToggleDarkModeTool(),
      createTogglePlatformTool(),
      createToggleDebugPaintTool(),
      createToggleRepaintRainbowTool(),
      createToggleSlowAnimationsTool(),
      createTogglePerformanceOverlayTool(),

      // Performance tracking
      createTrackRebuildsTool(),
      createTrackRepaintsTool(),
    ],
  ).run();
}
