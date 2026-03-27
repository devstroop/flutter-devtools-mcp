import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service_io.dart';

/// Debug: find Semantics nodes and dump their detail properties.
void main() async {
  final url = Platform.environment['FLUTTER_VM_SERVICE_URL'] ??
      'ws://127.0.0.1:58538/ws';
  stderr.writeln('Connecting to $url ...');

  final service = await vmServiceConnectUri(url);
  final vm = await service.getVM();
  final isolateId = vm.isolates!.first.id!;

  // Get summary tree
  final treeResp = await service.callServiceExtension(
    'ext.flutter.inspector.getRootWidgetSummaryTree',
    isolateId: isolateId,
    args: {'objectGroup': 'debug-sem'},
  );
  final tree = treeResp.json!;
  final result = (tree.containsKey('result') && tree['result'] is Map)
      ? Map<String, Object?>.from(tree['result'] as Map)
      : tree;

  // Find all Semantics nodes
  final semanticsNodes = <Map<String, Object?>>[];
  _findByType(result, 'Semantics', semanticsNodes);
  stderr.writeln('Found ${semanticsNodes.length} Semantics nodes');

  final encoder = JsonEncoder.withIndent('  ');

  for (final node in semanticsNodes.take(3)) {
    final valueId = node['valueId'] as String;
    stderr.writeln('\n--- Semantics node: $valueId ---');
    stderr.writeln('Summary: ${encoder.convert({
      'description': node['description'],
      'valueId': node['valueId'],
      'widgetRuntimeType': node['widgetRuntimeType'],
    })}');

    // Fetch details
    final detailResp = await service.callServiceExtension(
      'ext.flutter.inspector.getDetailsSubtree',
      isolateId: isolateId,
      args: {
        'objectGroup': 'debug-sem',
        'arg': valueId,
        'subtreeDepth': '0',
      },
    );
    final detailJson = detailResp.json!;
    stderr.writeln('Detail response top keys: ${detailJson.keys.toList()}');

    // Unwrap result if present
    final detail = (detailJson.containsKey('result') && detailJson['result'] is Map)
        ? Map<String, Object?>.from(detailJson['result'] as Map)
        : detailJson;
    stderr.writeln('Detail keys: ${detail.keys.toList()}');

    final props = detail['properties'] as List<Object?>?;
    if (props != null) {
      stderr.writeln('Properties (${props.length}):');
      for (final p in props) {
        if (p is Map<String, Object?>) {
          stderr.writeln('  ${p['name']}: ${p['description']} (type: ${p['type']})');
        }
      }
    } else {
      stderr.writeln('No properties!');
    }
  }

  await service.dispose();
}

void _findByType(Map<String, Object?> node, String type, List<Map<String, Object?>> out) {
  if (node['widgetRuntimeType'] == type) {
    out.add(node);
  }
  final children = node['children'] as List<Object?>?;
  if (children != null) {
    for (final child in children) {
      if (child is Map<String, Object?>) _findByType(child, type, out);
    }
  }
}
