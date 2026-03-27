/// Transforms Flutter DiagnosticsNode data into LLM-friendly JSON.
///
/// This is the "API surface" that downstream consumers depend on.
/// Keep it consistent, minimal, and predictable.
library;

/// Transform a raw inspector summary tree into LLM-friendly node list.
///
/// Output per node:
/// ```json
/// {
///   "id": "inspector-0x12345",
///   "type": "ElevatedButton",
///   "label": "Submit",
///   "key": "submit_btn",
///   "bounds": { "x": 120, "y": 540, "w": 200, "h": 48 },
///   "visible": true,
///   "enabled": true,
///   "inScrollable": false,
///   "children": [...]
/// }
/// ```
Map<String, Object?> transformTree(
  Map<String, Object?> rawNode, {
  bool inScrollable = false,
}) {
  final result = <String, Object?>{
    'id': rawNode['valueId'] ?? rawNode['objectId'],
    'type': rawNode['description'] ?? rawNode['widgetRuntimeType'] ?? 'Unknown',
  };

  // Extract key (from properties or creationLocation)
  final properties = rawNode['properties'] as List<Object?>?;
  String? label;
  bool? enabled;

  if (properties != null) {
    for (final prop in properties) {
      if (prop is Map<String, Object?>) {
        final name = prop['name'] as String?;
        final desc = (prop['description'] ?? prop['value'])?.toString();
        if (name == 'key') {
          result['key'] = desc;
        }
        if (name == 'label' || name == 'semanticLabel') {
          label = desc;
        }
        if (name == 'data' || name == 'text') {
          result['text'] = desc;
        }
        // Detect disabled state
        if ((name == 'enabled' && desc == 'false') ||
            (name == 'onPressed' && desc == 'null') ||
            (name == 'onTap' && desc == 'null')) {
          enabled = false;
        }
      }
    }
  }

  // Semantics label — populated by getDetailsSubtree enrichment
  if (rawNode['label'] != null) {
    result['label'] = rawNode['label'];
  } else if (label != null) {
    result['label'] = label;
  }

  // Extract bounds from render object if available
  final renderObject = rawNode['renderObject'] as Map<String, Object?>?;
  if (renderObject != null) {
    final renderProps = renderObject['properties'] as List<Object?>?;
    if (renderProps != null) {
      final bounds = _extractBounds(renderProps);
      if (bounds != null) {
        result['bounds'] = bounds;
        final w = (bounds['w'] as num?) ?? 0;
        final h = (bounds['h'] as num?) ?? 0;
        result['visible'] = w > 0 && h > 0;
      }
    }
  }

  if (enabled != null) {
    result['enabled'] = enabled;
  }

  // Detect if this node is a scrollable
  final type = result['type'] as String? ?? '';
  final isScrollable = type.contains('ListView') ||
      type.contains('GridView') ||
      type.contains('ScrollView') ||
      type.contains('CustomScrollView') ||
      type.contains('SingleChildScrollView') ||
      type.contains('PageView');

  if (inScrollable || isScrollable) {
    result['inScrollable'] = true;
  }

  // Recurse children
  final children = rawNode['children'] as List<Object?>?;
  if (children != null && children.isNotEmpty) {
    result['children'] = [
      for (final child in children)
        if (child is Map<String, Object?>)
          transformTree(child, inScrollable: inScrollable || isScrollable),
    ];
  }

  return result;
}

/// Extract bounds from render object properties.
Map<String, Object?>? _extractBounds(List<Object?> properties) {
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
          final m = RegExp(r'Size\(([\d.]+),\s*([\d.]+)\)').firstMatch(desc);
          if (m != null) {
            width = double.tryParse(m.group(1)!);
            height = double.tryParse(m.group(2)!);
          }
        case 'offset':
        case 'paintOffset':
          final m = RegExp(r'Offset\(([\d.]+),\s*([\d.]+)\)').firstMatch(desc);
          if (m != null) {
            x = double.tryParse(m.group(1)!);
            y = double.tryParse(m.group(2)!);
          }
        case 'paintBounds':
        case 'semanticBounds':
          final m = RegExp(
            r'Rect\.fromLTWH\(([\d.]+),\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)\)',
          ).firstMatch(desc);
          if (m != null) {
            x ??= double.tryParse(m.group(1)!);
            y ??= double.tryParse(m.group(2)!);
            width ??= double.tryParse(m.group(3)!);
            height ??= double.tryParse(m.group(4)!);
          }
      }
    }
  }

  if (width != null && height != null) {
    return {'x': x ?? 0, 'y': y ?? 0, 'w': width, 'h': height};
  }
  return null;
}

/// Flatten a transformed tree into a list of nodes (depth-first).
List<Map<String, Object?>> flattenTree(Map<String, Object?> tree) {
  final nodes = <Map<String, Object?>>[];
  _flatten(tree, nodes);
  return nodes;
}

void _flatten(Map<String, Object?> node, List<Map<String, Object?>> out) {
  // Add node without children to flat list
  final flat = Map<String, Object?>.from(node)..remove('children');
  out.add(flat);

  final children = node['children'] as List<Object?>?;
  if (children != null) {
    for (final child in children) {
      if (child is Map<String, Object?>) {
        _flatten(child, out);
      }
    }
  }
}
