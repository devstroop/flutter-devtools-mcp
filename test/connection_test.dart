import 'package:test/test.dart';
import 'package:flutter_devtools_mcp/src/connection.dart';
import 'package:flutter_devtools_mcp/src/connection_factory.dart';

void main() {
  group('FlutterConnection', () {
    group('constructor', () {
      test('accepts localhost URL', () {
        final conn = FlutterConnection(vmServiceUrl: 'ws://localhost:12345/ws');
        expect(conn.vmServiceUrl, 'ws://localhost:12345/ws');
      });

      test('accepts 127.0.0.1 URL', () {
        final conn = FlutterConnection(vmServiceUrl: 'ws://127.0.0.1:54321/ws');
        expect(conn.vmServiceUrl, 'ws://127.0.0.1:54321/ws');
      });

      test('accepts ::1 URL', () {
        final conn = FlutterConnection(vmServiceUrl: 'ws://[::1]:12345/ws');
        expect(conn.vmServiceUrl, 'ws://[::1]:12345/ws');
      });

      test('rejects remote URL', () {
        expect(
          () => FlutterConnection(vmServiceUrl: 'ws://10.0.0.1:1234/ws'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('rejects hostname URL', () {
        expect(
          () => FlutterConnection(vmServiceUrl: 'ws://example.com:1234/ws'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('rejects malformed URL', () {
        expect(
          () => FlutterConnection(vmServiceUrl: 'not a url at all'),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('URL normalization', () {
      test('converts http:// to ws:// and appends /ws', () {
        final conn = FlutterConnection(vmServiceUrl: 'http://127.0.0.1:12345/');
        expect(conn.vmServiceUrl, 'ws://127.0.0.1:12345/ws');
      });

      test('converts https:// to wss://', () {
        final conn =
            FlutterConnection(vmServiceUrl: 'https://127.0.0.1:12345/');
        expect(conn.vmServiceUrl, 'wss://127.0.0.1:12345/ws');
      });

      test('preserves existing ws:// scheme', () {
        final conn = FlutterConnection(vmServiceUrl: 'ws://127.0.0.1:54321/ws');
        expect(conn.vmServiceUrl, 'ws://127.0.0.1:54321/ws');
      });

      test('preserves auth token path segment', () {
        final conn = FlutterConnection(
          vmServiceUrl: 'ws://127.0.0.1:54321/abc123=/ws',
        );
        expect(conn.vmServiceUrl, 'ws://127.0.0.1:54321/abc123=/ws');
      });

      test('normalizes http URL with auth token', () {
        final conn = FlutterConnection(
          vmServiceUrl: 'http://127.0.0.1:54321/Ex97WPNegP0=/',
        );
        expect(
          conn.vmServiceUrl,
          'ws://127.0.0.1:54321/Ex97WPNegP0=/ws',
        );
      });
    });

    group('pre-connect access', () {
      late FlutterConnection conn;

      setUp(() {
        conn = FlutterConnection(vmServiceUrl: 'ws://127.0.0.1:12345/ws');
      });

      test('service throws StateError before connect', () {
        expect(() => conn.service, throwsA(isA<StateError>()));
      });

      test('isolateId throws StateError before connect', () {
        expect(() => conn.isolateId, throwsA(isA<StateError>()));
      });

      test('rootLibraryId throws StateError before connect', () {
        expect(() => conn.rootLibraryId, throwsA(isA<StateError>()));
      });
    });

    group('disconnect', () {
      test('disconnect on unconnected instance does not throw', () async {
        final conn = FlutterConnection(vmServiceUrl: 'ws://127.0.0.1:12345/ws');
        // Should not throw even when not connected
        await conn.disconnect();
        expect(() => conn.service, throwsA(isA<StateError>()));
      });
    });
  });

  group('ConnectionFactory', () {
    test('starts with no connections', () {
      final factory = ConnectionFactory();
      expect(factory.hasConnection, false);
    });

    test('disconnectAll on empty cache does not throw', () async {
      final factory = ConnectionFactory();
      await factory.disconnectAll();
      expect(factory.hasConnection, false);
    });

    test('double disconnectAll is safe', () async {
      final factory = ConnectionFactory();
      await factory.disconnectAll();
      await factory.disconnectAll();
      expect(factory.hasConnection, false);
    });
  });
}
