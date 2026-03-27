import 'package:test/test.dart';
import 'package:flutter_devtools_mcp/src/discovery.dart';

void main() {
  group('DiscoveredVmService', () {
    group('wsUrl', () {
      test('builds URL without authCode', () {
        final svc = DiscoveredVmService(port: 54321);
        expect(svc.wsUrl, 'ws://127.0.0.1:54321/ws');
      });

      test('builds URL with authCode', () {
        final svc = DiscoveredVmService(port: 54321, authCode: 'abc123');
        expect(svc.wsUrl, 'ws://127.0.0.1:54321/abc123=/ws');
      });

      test('treats empty authCode same as no authCode', () {
        final svc = DiscoveredVmService(port: 12345, authCode: '');
        expect(svc.wsUrl, 'ws://127.0.0.1:12345/ws');
      });

      test('toString returns wsUrl', () {
        final svc = DiscoveredVmService(port: 8888);
        expect(svc.toString(), svc.wsUrl);
      });
    });
  });
}
