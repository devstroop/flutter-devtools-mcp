import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

import '../mcp_transport.dart';

final _log = Logger('ListDevices');

/// MCP tool: list_devices
///
/// List available Flutter devices by running `flutter devices --machine`.
ToolDef createListDevicesTool() {
  return ToolDef(
    name: 'list_devices',
    description: 'List available Flutter devices and emulators by running '
        '`flutter devices --machine`. Returns device name, ID, platform, '
        'and whether it is emulated.',
    inputSchema: {
      'type': 'object',
      'properties': {},
    },
    handler: (args) async {
      try {
        final result = await Process.run(
          Platform.isWindows ? 'flutter.bat' : 'flutter',
          ['devices', '--machine'],
          runInShell: true,
        );

        if (result.exitCode != 0) {
          return {
            'content': [
              {
                'type': 'text',
                'text': '{"status":"error","error":"flutter devices failed: '
                    '${(result.stderr as String).trim()}"}',
              },
            ],
          };
        }

        final raw = (result.stdout as String).trim();
        if (raw.isEmpty) {
          return {
            'content': [
              {
                'type': 'text',
                'text': '{"status":"success","devices":[]}',
              },
            ],
          };
        }

        final devices = jsonDecode(raw) as List<dynamic>;
        final mapped = devices.map((d) {
          final m = d as Map<String, dynamic>;
          return {
            'name': m['name'],
            'id': m['id'],
            'platform': m['platform'],
            'emulator': m['emulator'] ?? false,
          };
        }).toList();

        _log.info('Found ${mapped.length} device(s)');
        return {
          'content': [
            {
              'type': 'text',
              'text': json.encode({'status': 'success', 'devices': mapped}),
            },
          ],
        };
      } catch (e) {
        _log.warning('list_devices failed: $e');
        return {
          'isError': true,
          'content': [
            {'type': 'text', 'text': 'Failed to list devices: $e'},
          ],
        };
      }
    },
  );
}
