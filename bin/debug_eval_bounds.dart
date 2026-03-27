import 'dart:io';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Debug: try evaluate() to get widget bounds via WidgetInspectorService.
void main() async {
  final url = 'ws://127.0.0.1:58538/ws';
  final service = await vmServiceConnectUri(url);
  final vm = await service.getVM();
  final isolate = vm.isolates!.first;
  final isolateId = isolate.id!;

  // Find root library
  final isolateObj = await service.getIsolate(isolateId);
  final rootLib = isolateObj.rootLib!.id!;
  print('Root library: $rootLib');

  // Try setSelectionById then get bounds via evaluate
  // First, select the widget by inspector ID
  try {
    final selectResp = await service.callServiceExtension(
      'ext.flutter.inspector.setSelectionById',
      isolateId: isolateId,
      args: {'objectGroup': 'mcp-bounds', 'arg': 'inspector-224'},
    );
    print('setSelectionById response: ${selectResp.json}');
  } catch (e) {
    print('setSelectionById failed: $e');
  }

  // Try to get the bounds via evaluate
  final expressions = [
    // Approach 1: Use WidgetInspectorService.instance.selection
    '(() { final selection = WidgetInspectorService.instance.selection; if (selection == null || selection.current == null) return "no-selection"; final ro = selection.current!.findRenderObject(); if (ro is! RenderBox || !ro.hasSize) return "no-renderbox"; final offset = ro.localToGlobal(Offset.zero); return "\${offset.dx},\${offset.dy},\${ro.size.width},\${ro.size.height}"; })()',
    // Approach 2: Direct WidgetInspectorService.toObject
    '(() { final obj = WidgetInspectorService.instance.toObject("inspector-224", "mcp-bounds"); if (obj is! Element) return "not-element:\${obj.runtimeType}"; final ro = obj.findRenderObject(); if (ro is! RenderBox || !ro.hasSize) return "no-renderbox"; final offset = ro.localToGlobal(Offset.zero); return "\${offset.dx},\${offset.dy},\${ro.size.width},\${ro.size.height}"; })()',
  ];

  for (var i = 0; i < expressions.length; i++) {
    print('\n--- Approach ${i + 1} ---');
    try {
      final result = await service.evaluate(isolateId, rootLib, expressions[i].trim());
      if (result is InstanceRef) {
        print('Result (${result.kind}): ${result.valueAsString}');
      } else if (result is ErrorRef) {
        print('Error: ${result.message}');
      } else {
        print('Unknown result type: ${result.runtimeType}');
      }
    } catch (e) {
      print('Evaluate failed: $e');
    }
  }

  await service.dispose();
}
