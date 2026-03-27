/// Transforms Flutter DiagnosticsNode data into LLM-friendly JSON.
///
/// This is the "API surface" that downstream consumers depend on.
/// Keep it consistent, minimal, and predictable.

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
Map<String, Object?> transformTree(Map<String, Object?> rawNode) {
  final result = <String, Object?>{
    'id': rawNode['valueId'] ?? rawNode['objectId'],
    'type': rawNode['description'] ?? rawNode['widgetRuntimeType'] ?? 'Unknown',
  };

  // Extract key (from properties or creationLocation)
  final properties = rawNode['properties'] as List<Object?>?;
  if (properties != null) {
    for (final prop in properties) {
      if (prop is Map<String, Object?>) {
        final name = prop['name'] as String?;
        if (name == 'key') {
          result['key'] = prop['description'] ?? prop['value'];
        }
      }
    }
  }

  // Semantics label — populated by getDetailsSubtree enrichment
  if (rawNode['label'] != null) {
    result['label'] = rawNode['label'];
  }

  // TODO: populate from render tree enrichment
  // result['bounds'] = ...
  // result['visible'] = ...
  // result['enabled'] = ...
  // result['inScrollable'] = ...

  // Recurse children
  final children = rawNode['children'] as List<Object?>?;
  if (children != null && children.isNotEmpty) {
    result['children'] = [
      for (final child in children)
        if (child is Map<String, Object?>) transformTree(child),
    ];
  }

  return result;
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
