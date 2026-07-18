import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

final _log = Logger('Registry');

/// A single entry in the VM Service registry.
class RegistryEntry {
  final String vmServiceUrl;
  final String projectPath;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final bool isActive;

  RegistryEntry({
    required this.vmServiceUrl,
    required this.projectPath,
    required this.firstSeen,
    required this.lastSeen,
    required this.isActive,
  });

  Map<String, dynamic> toJson() => {
        'vmServiceUrl': vmServiceUrl,
        'projectPath': projectPath,
        'firstSeen': firstSeen.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
        'isActive': isActive,
      };

  factory RegistryEntry.fromJson(Map<String, dynamic> j) => RegistryEntry(
        vmServiceUrl: j['vmServiceUrl'] as String,
        projectPath: j['projectPath'] as String? ?? '',
        firstSeen: DateTime.tryParse(j['firstSeen'] as String? ?? '') ??
            DateTime.now(),
        lastSeen:
            DateTime.tryParse(j['lastSeen'] as String? ?? '') ?? DateTime.now(),
        isActive: j['isActive'] as bool? ?? false,
      );

  Map<String, Object?> toToolResult() => {
        'url': vmServiceUrl,
        'project': projectPath.isNotEmpty ? projectPath : null,
        'active': isActive,
        'firstSeen': firstSeen.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
      };
}

/// Persistent registry of known VM Service URLs.
///
/// Stored at ~/.flutter_devtools_mcp/registry.json. Survives server
/// restarts so agents can reconnect without rescanning for URLs.
class Registry {
  static Registry? _instance;
  final File _file;
  final List<RegistryEntry> _entries = [];

  Registry._(this._file);

  static Registry get instance {
    if (_instance == null) {
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '/tmp';
      final dir = Directory('$home/.flutter_devtools_mcp');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _instance = Registry._(File('${dir.path}/registry.json'));
    }
    return _instance!;
  }

  List<RegistryEntry> get entries => List.unmodifiable(_entries);
  List<RegistryEntry> get active => _entries.where((e) => e.isActive).toList();

  /// Load registry from disk. Call once on startup.
  void load() {
    if (!_file.existsSync()) return;
    try {
      final raw = _file.readAsStringSync();
      final list = jsonDecode(raw) as List<dynamic>;
      _entries.clear();
      for (final item in list) {
        _entries.add(RegistryEntry.fromJson(item as Map<String, dynamic>));
      }
      _log.info('Loaded ${_entries.length} entries from registry');
    } catch (e) {
      _log.warning('Failed to load registry: $e');
    }
  }

  void _save() {
    try {
      final list = _entries.map((e) => e.toJson()).toList();
      _file.writeAsStringSync(jsonEncode(list), flush: true);
    } catch (e) {
      _log.warning('Failed to save registry: $e');
    }
  }

  /// Register or update a VM Service URL.
  void register(String vmServiceUrl, {String? projectPath}) {
    final existing =
        _entries.where((e) => e.vmServiceUrl == vmServiceUrl).firstOrNull;
    if (existing != null) {
      _entries.remove(existing);
      _entries.add(RegistryEntry(
        vmServiceUrl: vmServiceUrl,
        projectPath: projectPath ?? existing.projectPath,
        firstSeen: existing.firstSeen,
        lastSeen: DateTime.now(),
        isActive: true,
      ));
    } else {
      _entries.add(RegistryEntry(
        vmServiceUrl: vmServiceUrl,
        projectPath: projectPath ?? _inferProjectPath() ?? '',
        firstSeen: DateTime.now(),
        lastSeen: DateTime.now(),
        isActive: true,
      ));
    }
    _save();
  }

  /// Mark an entry as disconnected (keep history, just flip flag).
  void markDisconnected(String vmServiceUrl) {
    final idx = _entries.indexWhere((e) => e.vmServiceUrl == vmServiceUrl);
    if (idx < 0) return;
    _entries[idx] = RegistryEntry(
      vmServiceUrl: _entries[idx].vmServiceUrl,
      projectPath: _entries[idx].projectPath,
      firstSeen: _entries[idx].firstSeen,
      lastSeen: DateTime.now(),
      isActive: false,
    );
    _save();
  }

  /// Remove an entry entirely.
  void remove(String vmServiceUrl) {
    _entries.removeWhere((e) => e.vmServiceUrl == vmServiceUrl);
    _save();
  }

  /// Mark all active entries as disconnected (server shutdown).
  void markAllDisconnected() {
    for (var i = 0; i < _entries.length; i++) {
      if (_entries[i].isActive) {
        _entries[i] = RegistryEntry(
          vmServiceUrl: _entries[i].vmServiceUrl,
          projectPath: _entries[i].projectPath,
          firstSeen: _entries[i].firstSeen,
          lastSeen: DateTime.now(),
          isActive: false,
        );
      }
    }
    _save();
  }

  String? _inferProjectPath() {
    try {
      final cwd = Directory.current.path;
      if (File('$cwd/pubspec.yaml').existsSync()) return cwd;
      return null;
    } catch (_) {
      return null;
    }
  }
}
