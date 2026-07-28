import '../../models/command_log_entry.dart';

/// Hook that lets terminal internals hand finished commands to the command log
/// without importing cubits (mirrors `NotificationRecorder`).
abstract interface class CommandLogSink {
  void record(CommandLogEntry entry);

  static CommandLogSink? _current;

  static CommandLogSink? get maybeCurrent => _current;

  static void install(CommandLogSink? sink) {
    _current = sink;
  }
}
