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
  static StreamSubscription<String>? _stderrSub;
  static bool _killedByUs = false;

  /// Callback invoked when the process exits unexpectedly (not via [kill]).
  /// Set by the tool handler to trigger [CurrentConnection.disconnect].
  static void Function(int exitCode)? onUnexpectedExit;

  /// Whether a `flutter run` process is currently running.
  static bool get isRunning => _process != null;

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

    final process = await Process.start(
      'flutter',
      ['run', '-d', platform, '--debug'],
      workingDirectory: workingDirectory,
      runInShell: true,
    );
    _process = process;
    _killedByUs = false;

    _log.info('Started flutter run (pid: ${process.pid}) for $platform');

    // Forward stderr to our stderr and capture the VM Service URL.
    // We must keep reading stderr after the URL is found so the pipe
    // buffer doesn't fill up and block the child process.
    final urlCompleter = Completer<String>();
    _stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      stderr.writeln('[flutter_run] $line');
      if (!urlCompleter.isCompleted) {
        final match = _vmUrlPattern.firstMatch(line);
        if (match != null) {
          urlCompleter.complete(match.group(1)!);
        }
      }
    });

    try {
      final url = await urlCompleter.future.timeout(timeout);
      _log.info('Captured VM Service URL');

      final conn = FlutterConnection(vmServiceUrl: url);
      await conn.connect();
      _log.info('Connected to VM Service');

      // Watch for unexpected process exit and trigger cleanup.
      process.exitCode.then((code) {
        _process = null;
        _stderrSub = null;
        if (!_killedByUs) {
          stderr.writeln(
            '[flutter_run] Process exited unexpectedly (code: $code)',
          );
          onUnexpectedExit?.call(code);
        }
      });

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
    await _stderrSub?.cancel();
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
    r'A Dart VM Service is available at: (http://\S+)',
  );
}
