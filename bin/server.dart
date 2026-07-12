import 'dart:io';

import 'package:flutter_devtools_mcp/src/mcp_transport.dart';
import 'package:flutter_devtools_mcp/src/connection_factory.dart';

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
import 'package:flutter_devtools_mcp/src/tools/discover.dart';
import 'package:flutter_devtools_mcp/src/tools/status.dart';
import 'package:flutter_devtools_mcp/src/tools/launch.dart';
import 'package:flutter_devtools_mcp/src/tools/launch_status.dart';
import 'package:flutter_devtools_mcp/src/tools/stop_app.dart';

/// MCP server for Flutter UI automation via DevTools VM Service extensions.
///
/// Zero-config stdio server. Connects to Flutter apps via:
/// - Per-call vmServiceUrl parameter (explicit)
/// - mDNS auto-discovery (if vmServiceUrl omitted)
///
/// Build: dart compile exe bin/server.dart -o bin/flutter_devtools_mcp_server
void main() {
  final factory = ConnectionFactory();

  // Graceful shutdown — close all WebSocket connections
  ProcessSignal.sigint.watch().listen((_) async {
    await factory.disconnectAll();
    exit(0);
  });
  ProcessSignal.sigterm.watch().listen((_) async {
    await factory.disconnectAll();
    exit(0);
  });

  McpServer(
    name: 'flutter_devtools_mcp',
    version: '0.3.0',
    tools: [
      // Management / orchestration
      createConnectTool(factory),
      createDiscoverTool(factory),
      createStatusTool(factory),
      createLaunchTool(factory),
      createLaunchStatusTool(factory),
      createStopAppTool(factory),

      // Inspection
      createSnapshotTool(factory),
      createInspectTool(factory),
      createGetParentChainTool(factory),
      createGetRenderTreeTool(factory),
      createGetLayerTreeTool(factory),
      createDumpSemanticsTool(factory),

      // Interaction
      createTapTool(factory),
      createTypeTextTool(factory),
      createScrollTool(factory),
      createPressBackTool(factory),
      createScreenshotTool(factory),

      // Flutter lifecycle
      createHotReloadTool(factory),
      createHotRestartTool(factory),
      createEvaluateTool(factory),
      createGetErrorsTool(factory),
      createGetLogsTool(factory),
      createGetMemoryTool(factory),

      // Overlay toggles
      createToggleDarkModeTool(factory),
      createTogglePlatformTool(factory),
      createToggleDebugPaintTool(factory),
      createToggleRepaintRainbowTool(factory),
      createToggleSlowAnimationsTool(factory),
      createTogglePerformanceOverlayTool(factory),

      // Performance tracking
      createTrackRebuildsTool(factory),
      createTrackRepaintsTool(factory),
    ],
  ).run();
}
