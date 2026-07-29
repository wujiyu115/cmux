import 'package:teampilot/services/terminal/terminal_session.dart';

/// Recording [TerminalSession] for cubit / smoke tests that assert connect args.
class FakeTerminalSession extends TerminalSession {
  FakeTerminalSession({
    super.executable = 'flashskyai',
    super.scrollbackLines = 10000,
  });

  var _running = false;
  final lastWorkingDirectories = <String>[];
  final lastArgumentLists = <List<String>>[];
  final lastExtraEnvironments = <Map<String, String>?>[];

  @override
  bool get isRunning => _running;

  @override
  void connect({
    required String workingDirectory,
    List<String> arguments = const [],
    Map<String, String>? extraEnvironment,
    void Function()? onProcessStarted,
    void Function(String message)? onProcessFailed,
    void Function()? onProcessExited,
    void Function(String line)? onFirstUserLineSubmitted,
    void Function(String line)? onEveryUserLineSubmitted,
    String? executableOverride,
  }) {
    lastWorkingDirectories.add(workingDirectory);
    lastArgumentLists.add(List<String>.from(arguments));
    lastExtraEnvironments.add(
      extraEnvironment == null
          ? null
          : Map<String, String>.from(extraEnvironment),
    );
    _running = true;
    onProcessStarted?.call();
  }

  @override
  void disconnect() {
    _running = false;
  }

  @override
  void dispose() {
    _running = false;
  }
}
