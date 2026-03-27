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

/// Discover running Flutter VM Service instances via mDNS.
///
/// Flutter apps in debug mode broadcast their VM Service via the
/// `_dartobservatory._tcp` mDNS service type. This function listens
/// for responses for [timeout] and returns all found services.
///
/// If [timeout] expires with no results, returns an empty list.
Future<List<DiscoveredVmService>> discoverFlutterVmServices({
  Duration timeout = const Duration(seconds: 3),
}) async {
  final client = MDnsClient();
  final found = <DiscoveredVmService>[];

  try {
    await client.start();

    // Collect PTR records (service instance names)
    final instanceNames = <String>{};
    final ptrSub = client
        .lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer('_dartobservatory._tcp.local'),
        )
        .listen((ptr) {
      _log.fine('mDNS: found instance "${ptr.domainName}"');
      instanceNames.add(ptr.domainName);
    });

    await Future<void>.delayed(timeout);
    await ptrSub.cancel();

    if (instanceNames.isEmpty) {
      _log.fine('mDNS: no Flutter VM Services found');
      return found;
    }

    // Resolve SRV + TXT for each discovered instance
    for (final name in instanceNames) {
      int? port;
      String? authCode;

      // SRV → port number
      await for (final srv in client
          .lookup<SrvResourceRecord>(ResourceRecordQuery.service(name))
          .timeout(const Duration(seconds: 1), onTimeout: (_) {})) {
        port = srv.port;
        break; // first record is enough
      }

      if (port == null) {
        _log.fine('mDNS: no SRV record for "$name", skipping');
        continue;
      }

      // TXT → optional authCode
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
