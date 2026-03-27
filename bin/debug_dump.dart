import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service_io.dart';

/// Debug: dump the raw response from getRootWidgetSummaryTree.
void main() async {
  final url = Platform.environment['FLUTTER_VM_SERVICE_URL'] ?? 'ws://127.0.0.1:58538/ws';
  stderr.writeln('Connecting to $url ...');

  final service = await vmServiceConnectUri(url);
  final vm = await service.getVM();
  final isolateId = vm.isolates!.first.id!;
  stderr.writeln('Isolate: $isolateId');

  // Get the summary tree
  final response = await service.callServiceExtension(
    'ext.flutter.inspector.getRootWidgetSummaryTree',
    isolateId: isolateId,
    args: {'objectGroup': 'debug-dump'},
  );

  // Pretty print the top-level keys and first 2 levels of tree
  final data = response.json!;
  stderr.writeln('\n=== Response top-level keys: ${data.keys.toList()} ===\n');

  // Unwrap the 'result' key (service extension wrapper)
  final tree = (data.containsKey('result') && data['result'] is Map)
      ? Map<String, Object?>.from(data['result'] as Map)
      : data;
  stderr.writeln('=== Tree top-level keys: ${tree.keys.toList()} ===\n');

  // Dump full tree (no pruning)
  final encoder = JsonEncoder.withIndent('  ');
  final outFile = File('debug_tree.json');
  outFile.writeAsStringSync(encoder.convert(tree));
  stderr.writeln('Wrote tree to ${outFile.path} (${outFile.lengthSync()} bytes)');

  await service.dispose();
}

Map<String, Object?> _pruneTree(Map<String, Object?> node, {int maxDepth = 3, int depth = 0}) {
  final result = <String, Object?>{};
  for (final entry in node.entries) {
    if (entry.key == 'children' && entry.value is List) {
      final children = entry.value as List;
      if (depth >= maxDepth) {
        result['children'] = '... (${children.length} children)';
      } else {
        result['children'] = [
          for (final child in children.take(3))
            if (child is Map<String, Object?>)
              _pruneTree(child, maxDepth: maxDepth, depth: depth + 1),
          if (children.length > 3)
            '... and ${children.length - 3} more',
        ];
      }
    } else if (entry.key == 'properties' && entry.value is List) {
      final props = entry.value as List;
      result['properties'] = [
        for (final p in props.take(5))
          if (p is Map<String, Object?>) {'name': p['name'], 'description': p['description']},
        if (props.length > 5) '... and ${props.length - 5} more',
      ];
    } else {
      result[entry.key] = entry.value;
    }
  }
  return result;
}
