import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:multicast_dns/multicast_dns.dart';

final _log = Logger('Discovery');

/// A Flutter VM Service discovered via mDNS.
class DiscoveredVmService {
  final int port;
  final String? authCode;

  DiscoveredVmService({required this.port, this.authCode});

  /// WebSocket URL for this service.
  String get wsUrl {
    if (authCode != null && authCode!.isNotEmpty) {
      return 'ws://127.0.0.1:$port/$authCode=/ws';
    }
    return 'ws://127.0.0.1:$port/ws';
  }

  @override
  String toString() => wsUrl;
}

/// Discover running Flutter VM Service instances.
///
/// First tries mDNS (`_dartobservatory._tcp`), then falls back to
/// scanning for Dart listening ports via `lsof` and probing them via HTTP.
/// Returns ALL found services from both methods (deduplicated by port).
Future<List<DiscoveredVmService>> discoverFlutterVmServices({
  Duration timeout = const Duration(seconds: 3),
}) async {
  final byPort = <int, DiscoveredVmService>{};

  // Try mDNS first (fast, privacy-preserving)
  for (final svc in await _discoverViaMdns(timeout: timeout)) {
    byPort[svc.port] = svc;
  }

  // Fallback: HTTP/lsof scan (catches apps that don't broadcast mDNS)
  if (byPort.isEmpty) {
    _log.info('mDNS returned nothing — trying HTTP/lsof fallback...');
    for (final svc in await _discoverViaPortScan()) {
      byPort[svc.port] = svc;
    }
  }

  return byPort.values.toList();
}

/// mDNS discovery — listens for `_dartobservatory._tcp` broadcasts.
Future<List<DiscoveredVmService>> _discoverViaMdns({
  Duration timeout = const Duration(seconds: 3),
}) async {
  final client = MDnsClient();
  final found = <DiscoveredVmService>[];

  try {
    await client.start();

    final instanceNames = <String>{};
    final ptrSub = client
        .lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer('_dartobservatory._tcp.local'),
    )
        .listen((ptr) {
      instanceNames.add(ptr.domainName);
    });

    await Future<void>.delayed(timeout);
    await ptrSub.cancel();

    if (instanceNames.isEmpty) return found;

    for (final name in instanceNames) {
      int? port;
      String? authCode;

      await for (final srv in client
          .lookup<SrvResourceRecord>(ResourceRecordQuery.service(name))
          .timeout(const Duration(seconds: 1), onTimeout: (_) {})) {
        port = srv.port;
        break;
      }
      if (port == null) continue;

      await for (final txt in client
          .lookup<TxtResourceRecord>(ResourceRecordQuery.text(name))
          .timeout(const Duration(seconds: 1), onTimeout: (_) {})) {
        for (final entry in txt.text.split('\n')) {
          if (entry.startsWith('authCode=')) {
            authCode = entry.substring('authCode='.length).trim();
          }
        }
        break;
      }

      found.add(DiscoveredVmService(port: port, authCode: authCode));
      _log.info('mDNS: discovered VM Service at port $port');
    }
  } catch (e) {
    _log.warning('mDNS discovery failed: $e');
  } finally {
    client.stop();
  }
  return found;
}

/// Port-scan fallback — runs `lsof` to find Dart listening ports,
/// then probes each via HTTP to confirm it's a Dart VM Service.
///
/// Returns services WITHOUT auth codes (these can't be extracted from
/// process info). The user provides the full URL from `flutter run` output.
Future<List<DiscoveredVmService>> _discoverViaPortScan() async {
  final found = <DiscoveredVmService>[];
  try {
    // 1. Find all TCP LISTEN ports owned by dart processes
    final result = await Process.run(
      'lsof',
      ['-iTCP', '-sTCP:LISTEN', '-P', '-n', '-F', 'pcn'],
      runInShell: true,
    );
    if (result.exitCode != 0) return found;

    // Parse lsof output — format per record:
    //   p<PID>       ← process ID
    //   c<NAME>      ← command name
    //   n<ADDR>:PORT  ← network address
    final lines = (result.stdout as String).split('\n');
    final candidates = <({int pid, String cmd, int port})>{};
    int? currentPid;
    String? currentCmd;

    for (final line in lines) {
      if (line.startsWith('p')) {
        currentPid = int.tryParse(line.substring(1));
        currentCmd = null;
      } else if (line.startsWith('c')) {
        currentCmd = line.substring(1);
      } else if (line.startsWith('n') &&
          currentPid != null &&
          currentCmd != null) {
        final addr = line.substring(1);
        // Skip IPv6 addresses
        if (addr.startsWith('[')) continue;
        final colonIdx = addr.lastIndexOf(':');
        if (colonIdx == -1) continue;
        final port = int.tryParse(addr.substring(colonIdx + 1));
        if (port == null || port <= 0) continue;
        final cmd = currentCmd!.toLowerCase();
        if (cmd.contains('dart') || cmd.contains('dartvm')) {
          candidates.add((pid: currentPid, cmd: currentCmd!, port: port));
        }
      }
    }

    _log.fine('lsof: ${candidates.length} candidate ports');

    // 2. Probe each candidate port via HTTP to confirm it's a VM Service.
    //    The Dart VM Service returns 403 with "missing or invalid authentication code".
    for (final c in candidates) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(milliseconds: 500);
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${c.port}/'),
        );
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();

        if (body.contains('authentication code')) {
          found.add(DiscoveredVmService(port: c.port, authCode: null));
          _log.info('Port scan: confirmed VM Service at port ${c.port}');
        }
        client.close(force: true);
      } catch (_) {
        // Port probe failed — not a VM Service
      }
    }
  } catch (e) {
    _log.warning('Port-scan discovery failed: $e');
  }
  return found;
}

/// URI for the "connect" tool hint shown in error messages.
const String connectHint = '''
Paste the VM Service URL from your "flutter run" output:
  connect(vmServiceUrl: "http://127.0.0.1:PORT/TOKEN=/")

The output looks like:
  A Dart VM Service on macOS is available at: http://127.0.0.1:54321/abc123=/
                                                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                                    Copy this entire URL''';
