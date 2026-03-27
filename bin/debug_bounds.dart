import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service_io.dart';

/// Debug: dump getDetailsSubtree for ElevatedButton to understand bounds extraction.
void main() async {
  final url = 'ws://127.0.0.1:58538/ws';
  final service = await vmServiceConnectUri(url);
  final vm = await service.getVM();
  final isolateId = vm.isolates!.first.id!;

  // Get detail for the increment button (inspector-224)
  final resp = await service.callServiceExtension(
    'ext.flutter.inspector.getDetailsSubtree',
    isolateId: isolateId,
    args: {'objectGroup': 'debug', 'arg': 'inspector-224', 'subtreeDepth': '1'},
  );
  final detail = Map<String, Object?>.from(resp.json!['result'] as Map);
  final encoder = JsonEncoder.withIndent('  ');

  // Print key fields
  print('Keys: ${detail.keys.toList()}');
  
  // Check for renderObject
  final ro = detail['renderObject'];
  if (ro != null) {
    print('\nrenderObject type: ${ro.runtimeType}');
    if (ro is Map<String, Object?>) {
      print('RenderObject keys: ${ro.keys.toList()}');
      print('RenderObject description: ${ro['description']}');
      final roProps = ro['properties'] as List<Object?>?;
      if (roProps != null) {
        print('RenderObject properties (${roProps.length}):');
        for (final p in roProps) {
          if (p is Map<String, Object?>) {
            print('  ${p['name']}: ${p['description']}');
          }
        }
      }
    }
  } else {
    print('\nNo renderObject in detail!');
  }

  // Print all top-level properties
  final props = detail['properties'] as List<Object?>?;
  if (props != null) {
    print('\nWidget properties (${props.length}):');
    for (final p in props) {
      if (p is Map<String, Object?>) {
        print('  ${p['name']}: ${p['description']}');
      }
    }
  }

  // Also try getLayoutExplorerNode
  print('\n--- getLayoutExplorerNode ---');
  try {
    final layoutResp = await service.callServiceExtension(
      'ext.flutter.inspector.getLayoutExplorerNode',
      isolateId: isolateId,
      args: {'objectGroup': 'debug', 'id': 'inspector-224', 'subtreeDepth': '1'},
    );
    final layoutData = layoutResp.json!;
    final layout = (layoutData.containsKey('result') && layoutData['result'] is Map)
        ? Map<String, Object?>.from(layoutData['result'] as Map)
        : layoutData;
    print('Layout keys: ${layout.keys.toList()}');
    final layoutProps = layout['properties'] as List<Object?>?;
    if (layoutProps != null) {
      print('Layout properties (${layoutProps.length}):');
      for (final p in layoutProps) {
        if (p is Map<String, Object?>) {
          print('  ${p['name']}: ${p['description']}');
        }
      }
    }
    // Check renderObject in layout
    final layoutRo = layout['renderObject'];
    if (layoutRo is Map<String, Object?>) {
      print('\nlayout renderObject description: ${layoutRo['description']}');
      final roProps = layoutRo['properties'] as List<Object?>?;
      if (roProps != null) {
        print('layout renderObject properties (${roProps.length}):');
        for (final p in roProps) {
          if (p is Map<String, Object?>) {
            print('  ${p['name']}: ${p['description']}');
          }
        }
      }
    }
  } catch (e) {
    print('getLayoutExplorerNode failed: $e');
  }

  await service.dispose();
}
