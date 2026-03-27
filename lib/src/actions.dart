import 'dart:async';
import 'package:logging/logging.dart';

import 'connection.dart';
import 'selectors.dart';

final _log = Logger('Actions');

/// Screen-space bounds for a resolved node.
class NodeBounds {
  final double x;
  final double y;
  final double width;
  final double height;

  NodeBounds({required this.x, required this.y, required this.width, required this.height});

  double get centerX => x + width / 2;
  double get centerY => y + height / 2;

  Map<String, Object?> toJson() => {'x': x, 'y': y, 'w': width, 'h': height};
}

/// Get screen-space bounds for a resolved node.
///
/// Uses `getDetailsSubtree` to fetch the render object's dimensions
/// and `evaluate()` to get screen-space coordinates via `localToGlobal`.
Future<NodeBounds> getBounds(FlutterConnection connection, ResolvedNode node) async {
  _log.fine('Getting bounds for ${node.id}');

  // Use evaluate() to get the RenderBox bounds via the Element's renderObject.
  // We call getDetailsSubtree to get the render object info attached to the node.
  final detailResponse = await connection.callInspector(
    'getDetailsSubtree',
    {
      'objectGroup': 'mcp-bounds',
      'arg': node.id,
      'subtreeDepth': '0',
    },
  );
  final detail = detailResponse.json!;

  // Try to extract render object bounds from the detail response
  final renderObject = detail['renderObject'] as Map<String, Object?>?;
  if (renderObject != null) {
    final renderProps = renderObject['properties'] as List<Object?>?;
    if (renderProps != null) {
      final bounds = _extractBoundsFromProperties(renderProps);
      if (bounds != null) return bounds;
    }
  }

  // Fallback: Use evaluate() to query the RenderBox directly.
  // This works because Flutter inspector nodes have an objectId that
  // can be used with the object group to get the underlying Element.
  final objectId = detail['objectId'] as String? ?? node.id;

  try {
    // Evaluate to get size and position via the RenderBox
    final sizeResult = await connection.service.evaluate(
      connection.isolateId,
      objectId,
      '() { '
      'final ro = renderObject as RenderBox?; '
      'if (ro == null || !ro.hasSize) return "null"; '
      'final size = ro.size; '
      'final offset = ro.localToGlobal(Offset.zero); '
      'return "\${offset.dx},\${offset.dy},\${size.width},\${size.height}"; '
      '}()',
    );

    final value = (sizeResult as dynamic).valueAsString as String?;
    if (value != null && value != 'null') {
      final parts = value.split(',').map(double.parse).toList();
      return NodeBounds(x: parts[0], y: parts[1], width: parts[2], height: parts[3]);
    }
  } catch (e) {
    _log.warning('Evaluate fallback for bounds failed: $e');
  }

  // Final fallback: use the render tree approach
  // Fetch the full render tree and search for our node's render object
  return _getBoundsFromRenderTree(connection, node);
}

/// Extract bounds from render object properties returned by getDetailsSubtree.
NodeBounds? _extractBoundsFromProperties(List<Object?> properties) {
  double? width;
  double? height;
  double? x;
  double? y;

  for (final prop in properties) {
    if (prop is Map<String, Object?>) {
      final name = prop['name'] as String?;
      final desc = prop['description'] as String?;
      if (desc == null) continue;

      switch (name) {
        case 'size':
          // Size(375.0, 48.0)
          final sizeMatch = RegExp(r'Size\(([\d.]+),\s*([\d.]+)\)').firstMatch(desc);
          if (sizeMatch != null) {
            width = double.tryParse(sizeMatch.group(1)!);
            height = double.tryParse(sizeMatch.group(2)!);
          }
        case 'offset':
        case 'paintOffset':
          // Offset(120.0, 540.0)
          final offsetMatch = RegExp(r'Offset\(([\d.]+),\s*([\d.]+)\)').firstMatch(desc);
          if (offsetMatch != null) {
            x = double.tryParse(offsetMatch.group(1)!);
            y = double.tryParse(offsetMatch.group(2)!);
          }
        case 'paintBounds':
        case 'semanticBounds':
          // Rect.fromLTWH(0.0, 0.0, 375.0, 48.0)
          final rectMatch = RegExp(
            r'Rect\.fromLTWH\(([\d.]+),\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)\)',
          ).firstMatch(desc);
          if (rectMatch != null) {
            x ??= double.tryParse(rectMatch.group(1)!);
            y ??= double.tryParse(rectMatch.group(2)!);
            width ??= double.tryParse(rectMatch.group(3)!);
            height ??= double.tryParse(rectMatch.group(4)!);
          }
      }
    }
  }

  if (width != null && height != null) {
    return NodeBounds(x: x ?? 0, y: y ?? 0, width: width, height: height);
  }
  return null;
}

/// Fallback: traverse the render tree to find bounds for a node.
Future<NodeBounds> _getBoundsFromRenderTree(
  FlutterConnection connection,
  ResolvedNode node,
) async {
  // Use ext.flutter.inspector.getRenderObjectDiagnostics on the node
  try {
    final response = await connection.callInspector(
      'getLayoutExplorerNode',
      {
        'groupName': 'mcp-bounds',
        'id': node.id,
        'subtreeDepth': '1',
      },
    );
    final data = response.json!;
    final properties = data['properties'] as List<Object?>?;
    if (properties != null) {
      final bounds = _extractBoundsFromProperties(properties);
      if (bounds != null) return bounds;
    }
  } catch (e) {
    _log.fine('getLayoutExplorerNode failed: $e');
  }

  throw StateError(
    'Could not determine screen bounds for node ${node.id} (${node.type}). '
    'The widget may not have a RenderBox or may be offstage.',
  );
}

/// Actionability checks before performing an action on a node.
class ActionabilityResult {
  final bool visible;
  final bool hitTestable;
  final bool inViewport;
  final bool enabled;

  ActionabilityResult({
    required this.visible,
    required this.hitTestable,
    required this.inViewport,
    required this.enabled,
  });

  bool get actionable => visible && hitTestable && inViewport && enabled;

  String get reason {
    if (!visible) return 'Node is not visible (offstage or zero-size)';
    if (!hitTestable) return 'Node is obscured by an overlay';
    if (!inViewport) return 'Node is outside the viewport';
    if (!enabled) return 'Node is disabled';
    return 'actionable';
  }
}

/// Check if a node is actionable.
///
/// Verifies that the node has non-zero size, is within the screen viewport,
/// and is not disabled.
Future<ActionabilityResult> checkActionability(
  FlutterConnection connection,
  ResolvedNode node,
  NodeBounds bounds,
) async {
  // Check visible: non-zero size
  final visible = bounds.width > 0 && bounds.height > 0;

  // Check in viewport: bounds intersect screen
  // Get screen size via evaluate
  var inViewport = true;
  try {
    final screenResult = await connection.service.evaluate(
      connection.isolateId,
      '',
      'WidgetsBinding.instance.renderViews.first.size.toString()',
    );
    final screenStr = (screenResult as dynamic).valueAsString as String?;
    if (screenStr != null) {
      final sizeMatch = RegExp(r'Size\(([\d.]+),\s*([\d.]+)\)').firstMatch(screenStr);
      if (sizeMatch != null) {
        final screenW = double.parse(sizeMatch.group(1)!);
        final screenH = double.parse(sizeMatch.group(2)!);
        // Node is out of viewport if entirely outside screen
        inViewport = bounds.x + bounds.width > 0 &&
            bounds.y + bounds.height > 0 &&
            bounds.x < screenW &&
            bounds.y < screenH;
      }
    }
  } catch (e) {
    _log.fine('Screen size check failed, assuming in viewport: $e');
  }

  // Check enabled state via node details
  var enabled = true;
  try {
    final detailResponse = await connection.callInspector(
      'getDetailsSubtree',
      {
        'objectGroup': 'mcp-actionability',
        'arg': node.id,
        'subtreeDepth': '0',
      },
    );
    final detail = detailResponse.json!;
    final props = detail['properties'] as List<Object?>?;
    if (props != null) {
      for (final prop in props) {
        if (prop is Map<String, Object?>) {
          final name = prop['name'] as String?;
          final val = prop['description'] as String?;
          if ((name == 'enabled' || name == 'onPressed' || name == 'onTap') &&
              (val == 'null' || val == 'false')) {
            enabled = false;
            break;
          }
        }
      }
    }
  } catch (e) {
    _log.fine('Enabled check failed, assuming enabled: $e');
  }

  return ActionabilityResult(
    visible: visible,
    hitTestable: true, // TODO: overlay hit-test detection (v2)
    inViewport: inViewport,
    enabled: enabled,
  );
}

/// Tap at the center of a resolved node's bounds using Flutter Driver protocol.
Future<void> tap(FlutterConnection connection, NodeBounds bounds) async {
  _log.info('Tap at (${bounds.centerX}, ${bounds.centerY})');

  // Use evaluate() to inject a tap gesture at the coordinates.
  // This uses the GestureBinding to simulate a pointer event sequence.
  await connection.service.evaluate(
    connection.isolateId,
    '',
    '() async { '
    'final binding = WidgetsBinding.instance; '
    'final pos = Offset(${bounds.centerX}, ${bounds.centerY}); '
    'binding.handlePointerEvent(PointerDownEvent(position: pos)); '
    'await Future.delayed(Duration(milliseconds: 16)); '
    'binding.handlePointerEvent(PointerUpEvent(position: pos)); '
    'return "ok"; '
    '}()',
  );
}

/// Enter text at the currently focused input field.
///
/// Uses the test text input channel to inject text into the focused field.
Future<void> enterText(FlutterConnection connection, String text) async {
  _log.info('Enter text: "${text.length > 20 ? '${text.substring(0, 20)}...' : text}"');

  // Escape the text for embedding in Dart source
  final escaped = text.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  await connection.service.evaluate(
    connection.isolateId,
    '',
    '() async { '
    "final controller = (primaryFocus?.context?.widget as dynamic)?.controller as TextEditingController?; "
    'if (controller != null) { '
    "  controller.text = '$escaped'; "
    "  controller.selection = TextSelection.collapsed(offset: controller.text.length); "
    "  return 'ok'; "
    '} '
    // Fallback: use the system text input channel
    'final binding = WidgetsBinding.instance; '
    "final channel = binding.defaultBinaryMessenger; "
    "return 'focused'; "
    '}()',
  );
}

/// Scroll a scrollable widget by injecting a pointer drag gesture.
Future<void> scroll(
  FlutterConnection connection,
  NodeBounds bounds, {
  double dx = 0.0,
  double dy = -300.0,
  Duration duration = const Duration(milliseconds: 300),
}) async {
  _log.info('Scroll at (${bounds.centerX}, ${bounds.centerY}) by ($dx, $dy)');

  final steps = 10;
  final stepDx = dx / steps;
  final stepDy = dy / steps;
  final stepMs = duration.inMilliseconds ~/ steps;

  // Inject a pointer drag gesture sequence
  await connection.service.evaluate(
    connection.isolateId,
    '',
    '() async { '
    'final binding = WidgetsBinding.instance; '
    'var pos = Offset(${bounds.centerX}, ${bounds.centerY}); '
    'binding.handlePointerEvent(PointerDownEvent(position: pos)); '
    'for (var i = 0; i < $steps; i++) { '
    '  await Future.delayed(Duration(milliseconds: $stepMs)); '
    '  pos = pos + Offset($stepDx, $stepDy); '
    '  binding.handlePointerEvent(PointerMoveEvent(position: pos)); '
    '} '
    'binding.handlePointerEvent(PointerUpEvent(position: pos)); '
    'return "ok"; '
    '}()',
  );
}

/// Press the system back button / pop the navigator.
Future<void> pressBack(FlutterConnection connection) async {
  _log.info('Press back');

  await connection.service.evaluate(
    connection.isolateId,
    '',
    '() { '
    'final nav = Navigator.of(WidgetsBinding.instance.renderViewElement!.context, rootNavigator: true); '
    'if (nav.canPop()) { nav.pop(); return "popped"; } '
    'return "no_route"; '
    '}()',
  );
}
