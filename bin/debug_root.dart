import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service_io.dart';

/// Debug: dump just the root node keys from getRootWidgetSummaryTree.
void main() async {
  final url = Platform.environment['FLUTTER_VM_SERVICE_URL'] ?? 'ws://127.0.0.1:58538/ws';
  stderr.writeln('Connecting to $url ...');

  final service = await vmServiceConnectUri(url);
  final vm = await service.getVM();
  final isolateId = vm.isolates!.first.id!;

  final response = await service.callServiceExtension(
    'ext.flutter.inspector.getRootWidgetSummaryTree',
    isolateId: isolateId,
    args: {'objectGroup': 'debug-root'},
  );

  final json = response.json!;
  stderr.writeln('Root keys: ${json.keys.toList()}');
  stderr.writeln('Root type: ${json['type']}');
  stderr.writeln('Root description: ${json['description']}');
  stderr.writeln('Root valueId: ${json['valueId']}');
  stderr.writeln('Root widgetRuntimeType: ${json['widgetRuntimeType']}');
  stderr.writeln('Root hasChildren: ${json['hasChildren']}');
  stderr.writeln('Root children count: ${(json['children'] as List?)?.length}');

  // Also check a child
  final children = json['children'] as List?;
  if (children != null && children.isNotEmpty) {
    final child = children.first as Map<String, Object?>;
    stderr.writeln('\nFirst child keys: ${child.keys.toList()}');
    stderr.writeln('First child description: ${child['description']}');
    stderr.writeln('First child valueId: ${child['valueId']}');
    stderr.writeln('First child widgetRuntimeType: ${child['widgetRuntimeType']}');
  }

  await service.dispose();
}
