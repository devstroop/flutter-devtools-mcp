import 'dart:async';
import 'dart:io';

/// Shared state for launch/launch_status/stop_app tools.
///
/// Tracks the most recently launched flutter run subprocess.
class LaunchState {
  Process? process;
  String? projectPath;
  bool alive = false;
  final List<String> log = [];
}

final launchState = LaunchState();

/// Kill the currently tracked launched Flutter process.
void killLaunchedProcess() {
  final proc = launchState.process;
  if (proc == null) return;
  launchState.alive = false;
  try {
    proc.kill(ProcessSignal.sigterm);
    Future.delayed(const Duration(seconds: 2), () {
      try {
        proc.kill(ProcessSignal.sigkill);
      } catch (_) {}
    });
  } catch (_) {}
  launchState.process = null;
}
