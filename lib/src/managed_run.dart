import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

import 'connection.dart';

final _log = Logger('ManagedRun');

/// Manages a `flutter run --debug` child process.
///
/// Starts the process, captures the VM Service URL from stderr output,
/// creates a [FlutterConnection], and keeps the process alive for the
/// duration of the debugging session.
///
/// Call [kill] to terminate the process. The process is also killed
/// automatically when [CurrentConnection.disconnect] is called.
///
/// When the process exits unexpectedly (e.g. the app crashes or the user
/// quits it), [onUnexpectedExit] is invoked so the tool handler can
/// trigger a clean disconnect.
class ManagedFlutterRun {
  ManagedFlutterRun._();

  static Process? _process;
  static StreamSubscription<String>? _stdoutSub;
  static StreamSubscription<String>? _stderrSub;
  static bool _killedByUs = false;

  /// Cached path to the flutter binary, resolved once from PATH or common
  /// installation locations.
  static String? _flutterPath;

  /// Callback invoked when the process exits unexpectedly (not via [kill]).
  /// Set by the tool handler to trigger [CurrentConnection.disconnect].
  static void Function(int exitCode)? onUnexpectedExit;

  /// Whether a `flutter run` process is currently running.
  static bool get isRunning => _process != null;

  /// Resolve the path to the `flutter` binary.
  /// Tries `flutter --version` via shell first (covers all platforms when
  /// Flutter is on PATH, which is the common case for MCP users).
  /// Falls back to platform-specific known installation locations.
  static Future<String> _resolveFlutterBinary() async {
    if (_flutterPath != null) return _flutterPath!;

    // Fast path: try flutter directly through the shell. This works on
    // all platforms when flutter is on PATH (set via mcp.json env).
    try {
      final result = await Process.run(
        Platform.isWindows ? 'flutter.bat' : 'flutter',
        ['--version'],
        runInShell: true,
      ).timeout(const Duration(seconds: 10));
      if (result.exitCode == 0) {
        _flutterPath = Platform.isWindows ? 'flutter.bat' : 'flutter';
        return _flutterPath!;
      }
    } catch (_) {}

    // Fallback: platform-specific known installation directories.
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      final programFiles = Platform.environment['ProgramFiles'] ?? '';
      final candidates = [
        if (localAppData.isNotEmpty) '$localAppData\\Flutter\\bin\\flutter.bat',
        if (programFiles.isNotEmpty) '$programFiles\\Flutter\\bin\\flutter.bat',
        'C:\\tools\\flutter\\bin\\flutter.bat',
      ];
      for (final candidate in candidates) {
        if (await File(candidate).exists()) {
          _flutterPath = candidate;
          return candidate;
        }
      }
    } else {
      // macOS / Linux
      final home = Platform.environment['HOME'] ?? '';
      final candidates = [
        if (home.isNotEmpty) '$home/flutter/bin/flutter',
        if (home.isNotEmpty) '$home/snap/flutter/common/flutter/bin/flutter',
        '/opt/homebrew/bin/flutter',
        '/usr/local/bin/flutter',
        '/usr/bin/flutter',
        '/snap/bin/flutter',
      ];
      for (final candidate in candidates) {
        if (await File(candidate).exists()) {
          _flutterPath = candidate;
          return candidate;
        }
      }
    }

    throw StateError(
      'flutter not found. Install Flutter SDK from https://flutter.dev',
    );
  }

  /// Start `flutter run --debug` in [workingDirectory] for [platform],
  /// capture the VM Service URL, and return a connected [FlutterConnection].
  ///
  /// Throws [TimeoutException] if the URL is not captured within [timeout].
  /// Throws [StateError] if `flutter` is not found or the process fails.
  static Future<FlutterConnection> start({
    required String workingDirectory,
    required String platform,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    await kill();

    final flutterBin = await _resolveFlutterBinary();
    final process = await Process.start(
      flutterBin,
      ['run', '-d', platform, '--debug'],
      workingDirectory: workingDirectory,
      runInShell: true,
    );
    _process = process;
    _killedByUs = false;

    _log.info('Started flutter run (pid: ${process.pid}) for $platform');

    // The VM Service URL appears on stdout (not stderr). Forward both
    // streams to our stderr to keep pipe buffers drained and capture
    // the URL from whichever stream produces it.
    final urlCompleter = Completer<String>();

    void onLine(String line) {
      stderr.writeln('[flutter_run] $line');
      if (!urlCompleter.isCompleted) {
        final match = _vmUrlPattern.firstMatch(line);
        if (match != null) {
          urlCompleter.complete(match.group(1)!);
        }
      }
    }

    final stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine);
    final stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine);

    // Store in static fields so kill() can cancel them. Also capture the
    // pid and subscriptions locally into the exit handler closure so each
    // process can clean up its own subscriptions. A PID guard prevents the
    // exit handler from cancelling a subsequent process's subscriptions if
    // it fires after a new process has started.
    _stdoutSub = stdoutSub;
    _stderrSub = stderrSub;
    final capturedPid = process.pid;
    process.exitCode.then((code) {
      if (_process?.pid != capturedPid) return;
      _process = null;
      _stdoutSub = null;
      _stderrSub = null;
      stdoutSub.cancel();
      stderrSub.cancel();
      if (!_killedByUs) {
        stderr.writeln(
          '[flutter_run] Process exited unexpectedly (code: $code)',
        );
        onUnexpectedExit?.call(code);
      }
    });

    try {
      final url = await urlCompleter.future.timeout(timeout);
      _log.info('Captured VM Service URL');

      final conn = FlutterConnection(vmServiceUrl: url);
      await conn.connect();
      _log.info('Connected to VM Service');

      return conn;
    } catch (e) {
      // URL capture or connection failed — clean up the process.
      await kill();
      rethrow;
    }
  }

  /// Kill the running `flutter run` process.
  static Future<void> kill() async {
    final p = _process;
    if (p == null) return;
    _killedByUs = true;
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _process = null;
    p.kill(ProcessSignal.sigterm);
    // Give it a moment to exit gracefully, then force kill.
    await p.exitCode.timeout(const Duration(seconds: 3), onTimeout: () {
      p.kill(ProcessSignal.sigkill);
      return p.exitCode;
    });
    _log.info('Killed flutter run (pid: ${p.pid})');
  }

  static final RegExp _vmUrlPattern = RegExp(
    r'A Dart VM Service.*is available at: (http://\S+)',
  );
}
