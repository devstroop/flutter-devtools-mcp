import 'package:logging/logging.dart';

import 'connection.dart';

final _log = Logger('Selectors');

/// Selector tier, in order of preference.
enum SelectorTier {
  semantics, // semantics:label
  key,       // key:value_key
  text,      // text:content
  byIndex,   // index:Type:N
}

/// A parsed selector.
class Selector {
  final SelectorTier tier;
  final String value;
  final int? index; // only for SelectorTier.index

  Selector({required this.tier, required this.value, this.index});

  /// Parse a selector string.
  ///
  /// Formats:
  /// - `semantics:Submit`
  /// - `key:submit_btn`
  /// - `text:Submit`
  /// - `index:ElevatedButton:3`
  factory Selector.parse(String raw) {
    final colonIdx = raw.indexOf(':');
    if (colonIdx == -1) {
      // No prefix — treat as text search
      return Selector(tier: SelectorTier.text, value: raw);
    }
    final prefix = raw.substring(0, colonIdx).toLowerCase();
    final rest = raw.substring(colonIdx + 1);

    switch (prefix) {
      case 'semantics':
        return Selector(tier: SelectorTier.semantics, value: rest);
      case 'key':
        return Selector(tier: SelectorTier.key, value: rest);
      case 'text':
        return Selector(tier: SelectorTier.text, value: rest);
      case 'index':
        // index:Type:N
        final parts = rest.split(':');
        if (parts.length != 2) {
          throw FormatException('Index selector must be index:Type:N, got: $raw');
        }
        return Selector(
          tier: SelectorTier.byIndex,
          value: parts[0],
          index: int.parse(parts[1]),
        );
      default:
        // Unknown prefix — treat entire string as text
        return Selector(tier: SelectorTier.text, value: raw);
    }
  }

  @override
  String toString() {
    final prefix = tier == SelectorTier.byIndex ? 'index' : tier.name;
    return '$prefix:$value${index != null ? ':$index' : ''}';
  }
}

/// Result of resolving a selector against the widget tree.
class ResolvedNode {
  final String id;       // Inspector valueId
  final String type;     // Widget type name
  final String? label;   // Semantics label
  final String? key;     // Key value
  final String? text;    // Text content
  final SelectorTier matchedVia;

  ResolvedNode({
    required this.id,
    required this.type,
    this.label,
    this.key,
    this.text,
    required this.matchedVia,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    if (label != null) 'label': label,
    if (key != null) 'key': key,
    if (text != null) 'text': text,
    'matchedVia': matchedVia.name,
  };
}

/// Selector resolution error.
class SelectorError implements Exception {
  final String message;
  final int matchCount;
  final List<ResolvedNode> matches;

  SelectorError(this.message, {this.matchCount = 0, this.matches = const []});

  @override
  String toString() => 'SelectorError: $message (matches: $matchCount)';
}

/// Resolve a selector against the current widget tree.
///
/// Returns exactly one [ResolvedNode] or throws [SelectorError].
///
/// Rules:
/// - Exact match > partial match
/// - Visible nodes only (by default)
/// - Ambiguous matches → explicit error with match details
Future<ResolvedNode> resolveSelector(
  FlutterConnection connection,
  Selector selector, {
  bool visibleOnly = true,
}) async {
  _log.fine('Resolving: $selector');

  // 1. Fetch fresh summary tree
  final tree = await connection.callInspector(
    'getRootWidgetSummaryTree',
    {'objectGroup': 'mcp-selector'},
  );

  // 2. Collect all nodes from the summary tree
  final allNodes = <_FlatNode>[];
  _collectNodes(tree, allNodes);

  // 3. Resolve based on selector tier
  final matches = <ResolvedNode>[];

  switch (selector.tier) {
    case SelectorTier.key:
      // Keys are embedded in the description field: "WidgetType-[<'key_value'>]"
      for (final n in allNodes) {
        final key = _extractKeyFromDescription(n.description);
        if (key != null && key == selector.value) {
          matches.add(ResolvedNode(
            id: n.valueId,
            type: n.widgetType,
            key: key,
            matchedVia: SelectorTier.key,
          ));
        }
      }

    case SelectorTier.semantics:
      // Find Semantics widgets and fetch their label property
      final candidates = allNodes.where((n) => n.widgetType == 'Semantics').toList();
      for (final c in candidates) {
        final label = await _fetchSemanticsLabel(connection, c.valueId);
        if (label != null && label == selector.value) {
          // Return the Semantics node's CHILD as the resolved target
          // (the actionable widget is the child, not the Semantics wrapper)
          final childId = c.firstChildId ?? c.valueId;
          final childType = c.firstChildType ?? c.widgetType;
          matches.add(ResolvedNode(
            id: childId,
            type: childType,
            label: label,
            matchedVia: SelectorTier.semantics,
          ));
        }
      }

    case SelectorTier.text:
      // Find Text/RichText widgets and fetch their data property
      final candidates = allNodes.where(
        (n) => n.widgetType == 'Text' || n.widgetType == 'RichText',
      ).toList();
      for (final c in candidates) {
        final text = await _fetchTextData(connection, c.valueId);
        if (text != null && text == selector.value) {
          matches.add(ResolvedNode(
            id: c.valueId,
            type: c.widgetType,
            text: text,
            matchedVia: SelectorTier.text,
          ));
        }
      }

    case SelectorTier.byIndex:
      // Count widgets by type using widgetRuntimeType
      final counters = <String, int>{};
      for (final n in allNodes) {
        final count = counters[n.widgetType] ?? 0;
        if (n.widgetType == selector.value && count == selector.index) {
          matches.add(ResolvedNode(
            id: n.valueId,
            type: n.widgetType,
            matchedVia: SelectorTier.byIndex,
          ));
        }
        counters[n.widgetType] = count + 1;
      }
  }

  // 4. Resolve
  if (matches.isEmpty) {
    throw SelectorError('No node matches selector: $selector');
  }
  if (matches.length > 1 && selector.tier != SelectorTier.byIndex) {
    throw SelectorError(
      'Ambiguous: ${matches.length} nodes match "$selector". '
      'Use a more specific selector or provide an index.',
      matchCount: matches.length,
      matches: matches,
    );
  }

  final result = matches.first;
  if (result.matchedVia != SelectorTier.semantics) {
    _log.warning(
      'Selector "$selector" resolved via ${result.matchedVia.name} '
      '(not semantics). Consider adding a Semantics label.',
    );
  }
  return result;
}

/// Lightweight representation of a summary tree node.
class _FlatNode {
  final String valueId;
  final String description;
  final String widgetType;
  final String? firstChildId;
  final String? firstChildType;

  _FlatNode({
    required this.valueId,
    required this.description,
    required this.widgetType,
    this.firstChildId,
    this.firstChildType,
  });
}

/// Flatten the summary tree into a list of nodes.
void _collectNodes(Map<String, Object?> node, List<_FlatNode> out) {
  final valueId = node['valueId'] as String?;
  if (valueId == null) {
    // Skip nodes without IDs, but still recurse into children
    final children = node['children'] as List<Object?>?;
    if (children != null) {
      for (final child in children) {
        if (child is Map<String, Object?>) _collectNodes(child, out);
      }
    }
    return;
  }

  final description = node['description'] as String? ?? 'Unknown';
  final widgetType = node['widgetRuntimeType'] as String? ?? description;

  // Get the first child's identity (used for Semantics → child resolution)
  String? firstChildId;
  String? firstChildType;
  final children = node['children'] as List<Object?>?;
  if (children != null && children.isNotEmpty) {
    final first = children.first;
    if (first is Map<String, Object?>) {
      firstChildId = first['valueId'] as String?;
      firstChildType = first['widgetRuntimeType'] as String?;
    }
  }

  out.add(_FlatNode(
    valueId: valueId,
    description: description,
    widgetType: widgetType,
    firstChildId: firstChildId,
    firstChildType: firstChildType,
  ));

  // Recurse
  if (children != null) {
    for (final child in children) {
      if (child is Map<String, Object?>) _collectNodes(child, out);
    }
  }
}

/// Fetch the 'label' property from a Semantics widget via getDetailsSubtree.
Future<String?> _fetchSemanticsLabel(
  FlutterConnection connection,
  String nodeId,
) async {
  try {
    final detail = await connection.callInspector(
      'getDetailsSubtree',
      {'objectGroup': 'mcp-selector', 'arg': nodeId, 'subtreeDepth': '0'},
    );
    final properties = detail['properties'] as List<Object?>?;
    if (properties == null) return null;
    for (final prop in properties) {
      if (prop is Map<String, Object?>) {
        final name = prop['name'] as String?;
        if (name == 'label' || name == 'semanticLabel') {
          // Prefer 'value' (clean string) over 'description' (may have wrapping quotes)
          return (prop['value'] ?? _unquote(prop['description']))?.toString();
        }
      }
    }
  } catch (e) {
    _log.fine('Failed to fetch semantics label for $nodeId: $e');
  }
  return null;
}

/// Fetch the text content from a Text/RichText widget via getDetailsSubtree.
Future<String?> _fetchTextData(
  FlutterConnection connection,
  String nodeId,
) async {
  try {
    final detail = await connection.callInspector(
      'getDetailsSubtree',
      {'objectGroup': 'mcp-selector', 'arg': nodeId, 'subtreeDepth': '0'},
    );
    final properties = detail['properties'] as List<Object?>?;
    if (properties == null) return null;
    for (final prop in properties) {
      if (prop is Map<String, Object?>) {
        final name = prop['name'] as String?;
        if (name == 'data' || name == 'text') {
          return (prop['value'] ?? _unquote(prop['description']))?.toString();
        }
      }
    }
  } catch (e) {
    _log.fine('Failed to fetch text data for $nodeId: $e');
  }
  return null;
}

/// Strip wrapping double quotes from StringProperty description values.
/// Flutter's DiagnosticsNode.toJSON() wraps string descriptions in quotes.
Object? _unquote(Object? value) {
  if (value is String && value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

/// Extract a key value from a summary tree description like "ElevatedButton-[<'increment_btn'>]".
String? _extractKeyFromDescription(String description) {
  // Pattern: WidgetType-[<'key_value'>]
  final quoted = RegExp(r"\[<'(.+?)'>]").firstMatch(description);
  if (quoted != null) return quoted.group(1)!;

  // Pattern: WidgetType-[<key_value>]
  final unquoted = RegExp(r"\[<(.+?)>]").firstMatch(description);
  if (unquoted != null) return unquoted.group(1)!;

  return null;
}
