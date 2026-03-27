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
  final treeResponse = await connection.callInspector(
    'getRootWidgetSummaryTree',
    {'groupName': 'mcp-selector'},
  );
  final tree = treeResponse.json!;

  // 2. Walk tree and collect matches
  final matches = <ResolvedNode>[];
  _walkTree(tree, selector, matches);

  // 3. Apply visibility filter
  // TODO: filter by render object visibility when visibleOnly is true

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

void _walkTree(
  Map<String, Object?> node,
  Selector selector,
  List<ResolvedNode> matches, {
  Map<int, int>? typeCounters,
}) {
  typeCounters ??= {};

  // Extract node identity fields
  final valueId = node['valueId'] as String? ?? node['objectId'] as String?;
  final description = node['description'] as String? ??
      node['widgetRuntimeType'] as String? ??
      'Unknown';

  // Extract properties (label, key, text) from the node
  String? label;
  String? key;
  String? text;

  final properties = node['properties'] as List<Object?>?;
  if (properties != null) {
    for (final prop in properties) {
      if (prop is Map<String, Object?>) {
        final name = prop['name'] as String?;
        final value = (prop['description'] ?? prop['value'])?.toString();
        if (value == null || value.isEmpty) continue;
        switch (name) {
          case 'label':
          case 'semanticLabel':
            label = value;
          case 'key':
            // Strip Key wrapper e.g. [<'submit_btn'>] → submit_btn
            key = _stripKeyWrapper(value);
          case 'data':
          case 'text':
            text = value;
        }
      }
    }
  }

  // For Text widgets, also check description for inline text content
  if (text == null && (description.startsWith('Text') || description.startsWith('RichText'))) {
    // Text("Hello") shows as description = 'Text' with a 'data' property
    // Already handled above via 'data' property
  }

  // Track widget type count for index-based selector
  final typeKey = description.hashCode;
  final currentIndex = typeCounters[typeKey] ?? 0;
  typeCounters[typeKey] = currentIndex + 1;

  // Match against selector
  if (valueId != null) {
    final matched = _matchesSelector(
      selector: selector,
      type: description,
      label: label,
      key: key,
      text: text,
      typeIndex: currentIndex,
    );
    if (matched != null) {
      matches.add(ResolvedNode(
        id: valueId,
        type: description,
        label: label,
        key: key,
        text: text,
        matchedVia: matched,
      ));
    }
  }

  // Recurse into children
  final children = node['children'] as List<Object?>?;
  if (children != null) {
    for (final child in children) {
      if (child is Map<String, Object?>) {
        _walkTree(child, selector, matches, typeCounters: typeCounters);
      }
    }
  }
}

/// Check if a node matches the given selector. Returns the tier matched
/// or null if no match.
SelectorTier? _matchesSelector({
  required Selector selector,
  required String type,
  String? label,
  String? key,
  String? text,
  required int typeIndex,
}) {
  switch (selector.tier) {
    case SelectorTier.semantics:
      if (label != null && label == selector.value) {
        return SelectorTier.semantics;
      }
    case SelectorTier.key:
      if (key != null && key == selector.value) {
        return SelectorTier.key;
      }
    case SelectorTier.text:
      if (text != null && text == selector.value) {
        return SelectorTier.text;
      }
      // Also match against label and description for text searches
      if (label != null && label == selector.value) {
        return SelectorTier.text;
      }
    case SelectorTier.byIndex:
      if (type == selector.value && typeIndex == selector.index) {
        return SelectorTier.byIndex;
      }
  }
  return null;
}

/// Strip Flutter's Key wrapper syntax: [<'name'>] → name, ValueKey<String>#abcde(name) → name
String _stripKeyWrapper(String raw) {
  // Pattern: [<'value'>]
  final quoted = RegExp(r"\[<'(.+)'>\]").firstMatch(raw);
  if (quoted != null) return quoted.group(1)!;

  // Pattern: ValueKey<Type>#hash(value)
  final valueKey = RegExp(r'ValueKey<[^>]*>#\w+\((.+)\)').firstMatch(raw);
  if (valueKey != null) return valueKey.group(1)!;

  // Pattern: ValueKey<Type>(value)
  final simpleValueKey = RegExp(r'ValueKey<[^>]*>\((.+)\)').firstMatch(raw);
  if (simpleValueKey != null) return simpleValueKey.group(1)!;

  return raw;
}
