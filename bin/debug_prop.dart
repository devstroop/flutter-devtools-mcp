import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service_io.dart';

/// Debug: dump raw JSON of a single property to check quoting
void main() async {
  final url = 'ws://127.0.0.1:58538/ws';
  final service = await vmServiceConnectUri(url);
  final vm = await service.getVM();
  final isolateId = vm.isolates!.first.id!;

  // Fetch details for the first Semantics node (inspector-223)
  final detailResp = await service.callServiceExtension(
    'ext.flutter.inspector.getDetailsSubtree',
    isolateId: isolateId,
    args: {'objectGroup': 'debug', 'arg': 'inspector-223', 'subtreeDepth': '0'},
  );
  final detail = Map<String, Object?>.from(detailResp.json!['result'] as Map);
  final props = detail['properties'] as List<Object?>;
  
  // Find the 'label' property and dump it as raw JSON
  for (final p in props) {
    if (p is Map<String, Object?> && p['name'] == 'label') {
      final encoder = JsonEncoder.withIndent('  ');
      print('Raw label property JSON:');
      print(encoder.convert(p));
      print('');
      print('p["description"] type: ${p["description"].runtimeType}');
      print('p["description"] value: >${p["description"]}<');
      print('p["description"] length: ${(p["description"] as String?)?.length}');
      break;
    }
  }

  await service.dispose();
}
