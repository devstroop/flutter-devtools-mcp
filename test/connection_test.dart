import 'package:test/test.dart';
import 'package:flutter_devtools_mcp/src/connection.dart';

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
}
