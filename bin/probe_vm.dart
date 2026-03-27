import 'dart:io';
import 'package:vm_service/vm_service_io.dart';

/// Probe local ports to find a running Flutter VM Service.
///
/// Usage: dart run bin/probe_vm.dart [port1] [port2] ...
/// If no ports given, scans common ports.
void main(List<String> args) async {
  final ports = args.isNotEmpty
      ? args.map(int.parse).toList()
      : [58113, 58114]; // default ports from lsof

  for (final port in ports) {
    // Try without auth token first (direct ws)
    for (final path in ['/ws', '']) {
      final url = 'ws://127.0.0.1:$port$path';
      stderr.writeln('Trying $url ...');
      try {
        final service = await vmServiceConnectUri(url)
            .timeout(const Duration(seconds: 3));
        final vm = await service.getVM();
        final isolates = vm.isolates ?? [];
        print('SUCCESS: $url');
        print('  VM name: ${vm.name}');
        print('  Isolates: ${isolates.length}');
        for (final iso in isolates) {
          print('    - ${iso.name} (${iso.id})');
        }
        await service.dispose();
        exit(0);
      } catch (e) {
        stderr.writeln('  Failed: $e');
      }
    }
  }
  stderr.writeln('No VM Service found on any port.');
  exit(1);
}
