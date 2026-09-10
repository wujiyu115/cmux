import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_alacritty/links/terminal_link_provider.dart';
import 'package:flutter_alacritty/links/url_link_provider.dart';
import 'package:fake_async/fake_async.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace_shell_launch_plan.dart';
import 'package:teampilot/services/terminal/file_path_link_provider.dart';
import 'package:teampilot/services/terminal/terminal_export.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/terminal_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/flush_terminal_engine.dart';

class _FakeTransport implements TerminalTransport {
  final outputController = StreamController<Uint8List>();
  Completer<int> doneCompleter = Completer<int>();
  var closed = false;
  final resizeCalls = <(int, int)>[];
  final writes = <Uint8List>[];

  @override
  Stream<Uint8List> get output => outputController.stream;

  @override
  Future<int> get done => doneCompleter.future;

  @override
  int? get pid => null;

  @override
  void close() {
    closed = true;
    if (!doneCompleter.isCompleted) {
      doneCompleter.complete(0);
    }
  }

  @override
  void resize(int rows, int columns) {
    resizeCalls.add((rows, columns));
  }

  @override
  void write(Uint8List data) {
    writes.add(data);
  }
}

/// Passes [CliExecutableValidator] on the current platform. Tests use a fake
/// PTY, but [TerminalSession.connect] still runs pre-flight validation first.
String get _ptyTestExecutable {
  if (Platform.isWindows) {
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    return '$root\\System32\\cmd.exe';
  }
  // macOS runners often lack /bin/true; Linux has it at /bin/true.
  for (final candidate in ['/usr/bin/true', '/bin/true', '/bin/sh']) {
    if (File(candidate).existsSync()) return candidate;
  }
  return Platform.resolvedExecutable;
}

void main() {
  test('confirms on first pty output before fallback timer', () async {
    final handle = _FakeTransport();
    var started = false;
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      confirmFallback: const Duration(seconds: 5),
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(handle);
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(
      workingDirectory: Directory.systemTemp.path,
      onProcessStarted: () => started = true,
    );
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(started, isFalse);

    handle.outputController.add(Uint8List.fromList(utf8.encode('ready\r\n')));
    await Future<void>.delayed(Duration.zero);

    expect(started, isTrue);
    expect(session.isRunning, isTrue);
    expect(session.transportReadyForIo, isTrue);
  });

  test('transportReadyForIo is false before connect', () {
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      validateLaunch: false,
      parseExecutable: false,
    );
    addTearDown(session.dispose);
    expect(session.transportReadyForIo, isFalse);
  });

  test('silent startup confirms on fallback timer', () async {
    final handle = _FakeTransport();
    var started = false;
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      confirmFallback: const Duration(milliseconds: 50),
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(handle);
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(
      workingDirectory: Directory.systemTemp.path,
      onProcessStarted: () => started = true,
    );
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(started, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(started, isTrue);
  });

  test('process exit during startup reports failure', () async {
    final handle = _FakeTransport();
    var failed = false;
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      confirmFallback: const Duration(seconds: 5),
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(handle);
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(
      workingDirectory: Directory.systemTemp.path,
      onProcessStarted: () {},
      onProcessFailed: (_) => failed = true,
    );
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    handle.doneCompleter.complete(127);
    await Future<void>.delayed(Duration.zero);

    expect(failed, isTrue);
    expect(session.isRunning, isFalse);
    await flushTerminalEngine(session.engine);
    expect(
      exportTerminalScrollback(session.engine),
      contains('exited with code 127 during startup'),
    );
  });

  test('spawn timeout reports failure when transport never attaches', () async {
    final starter = Completer<TerminalTransport>();
    var failed = false;
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      spawnDeadline: const Duration(milliseconds: 80),
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return starter.future;
          },
    );
    addTearDown(session.dispose);

    session.connect(
      workingDirectory: Directory.systemTemp.path,
      onProcessFailed: (_) => failed = true,
    );
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(failed, isTrue);
    expect(session.isRunning, isFalse);
    await flushTerminalEngine(session.engine);
    expect(
      exportTerminalScrollback(session.engine),
      contains('spawn timed out'),
    );
  });

  test('missing absolute executable fails fast without starting pty', () async {
    var started = false;
    final session = TerminalSession(
      executable: '/tmp/teampilot-missing-flashskyai-executable',
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            started = true;
            return Future.value(_FakeTransport());
          },
    );
    addTearDown(session.dispose);

    session.connect(workingDirectory: Directory.current.path);
    session.onViewportResize(80, 24);
    await flushTerminalEngine(session.engine);

    expect(started, isFalse);
    expect(session.isRunning, isFalse);
    await flushTerminalEngine(session.engine);
    expect(
      exportTerminalScrollback(session.engine),
      anyOf(contains('not found'), contains('未找到')),
    );
  });

  test('stays running while exitCode has not completed', () async {
    final handle = _FakeTransport();
    final exitNever = Completer<int>();
    handle.doneCompleter = exitNever;

    final session = TerminalSession(
      executable: _ptyTestExecutable,
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(handle);
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: Directory.systemTemp.path);
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(session.isRunning, isTrue);

    await Future<void>.delayed(const Duration(seconds: 2));
    expect(session.isRunning, isTrue);
  });

  test('clean exit stops running and notifies onProcessExited', () async {
    final handle = _FakeTransport();
    var exited = false;

    final session = TerminalSession(
      executable: _ptyTestExecutable,
      validateLaunch: false,
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(handle);
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(
      workingDirectory: Directory.systemTemp.path,
      onProcessExited: () => exited = true,
    );
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(session.isRunning, isTrue);

    handle.doneCompleter.complete(0);
    await Future<void>.delayed(Duration.zero);
    await handle.done;

    expect(exited, isTrue);
    expect(session.isRunning, isFalse);
    expect(handle.closed, isTrue);
    await flushTerminalEngine(session.engine);
    expect(
      exportTerminalScrollback(session.engine),
      isNot(contains('[process exited]')),
    );
  });

  test('non-zero exit keeps terminal running for inspection', () async {
    final handle = _FakeTransport();

    final session = TerminalSession(
      executable: _ptyTestExecutable,
      validateLaunch: false,
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(handle);
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: Directory.systemTemp.path);
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    handle.doneCompleter.complete(1);
    await Future<void>.delayed(Duration.zero);
    await handle.done;

    expect(session.isRunning, isTrue);
    await flushTerminalEngine(session.engine);
    expect(
      exportTerminalScrollback(session.engine),
      contains('[process exited with code 1]'),
    );
  });

  test('exec failure output during confirming reports failure', () async {
    final handle = _FakeTransport();
    var failed = false;
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      confirmFallback: const Duration(seconds: 5),
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(handle);
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(
      workingDirectory: Directory.current.path,
      onProcessFailed: (_) => failed = true,
    );
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    handle.outputController.add(
      Uint8List.fromList(utf8.encode('execvp: No such file or directory\r\n')),
    );
    await Future<void>.delayed(Duration.zero);

    expect(failed, isTrue);
    expect(session.isRunning, isFalse);
  });

  test(
    'connect spawns pty with default viewport without TerminalView resize',
    () async {
      final starts = <({int columns, int rows})>[];
      final handle = _FakeTransport();
      final session = TerminalSession(
        executable: _ptyTestExecutable,
        transportStarter:
            (
              executable, {
              required arguments,
              required workingDirectory,
              required columns,
              required rows,
              environment,
            }) {
              starts.add((columns: columns, rows: rows));
              return Future.value(handle);
            },
      );
      addTearDown(() async {
        session.dispose();
        await handle.outputController.close();
      });

      session.connect(workingDirectory: Directory.systemTemp.path);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(starts, [(columns: 80, rows: 24)]);
      expect(session.isRunning, isTrue);
    },
  );

  test('connect starts pty on first terminal resize', () async {
    final starts = <({int columns, int rows})>[];
    final handle = _FakeTransport();
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            starts.add((columns: columns, rows: rows));
            return Future.value(handle);
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: Directory.systemTemp.path);
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(starts, [(columns: 80, rows: 24)]);
    expect(session.isRunning, isTrue);
  });

  test('rapid layout resizes debounce to final geometry', () async {
    final starts = <({int columns, int rows})>[];
    final handle = _FakeTransport();
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            starts.add((columns: columns, rows: rows));
            return Future.value(handle);
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: Directory.systemTemp.path);
    session.onViewportResize(80, 24);
    session.onViewportResize(100, 30);
    session.onViewportResize(120, 32);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(starts, [(columns: 80, rows: 24)]);
    expect(handle.resizeCalls, isNotEmpty);
    expect(handle.resizeCalls.last, (32, 120));
  });

  test('terminal resize resizes an already-started pty', () async {
    final handle = _FakeTransport();
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(handle);
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: Directory.systemTemp.path);
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    handle.resizeCalls.clear();

    session.onViewportResize(80, 24);
    session.onViewportResize(120, 32);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(handle.resizeCalls, contains((32, 120)));
    expect(handle.resizeCalls.last, (32, 120));
  });

  test('pty output is written to the terminal buffer', () async {
    final handle = _FakeTransport();
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(handle);
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: Directory.systemTemp.path);
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    handle.outputController.add(Uint8List.fromList(utf8.encode('hello\r\n')));
    await Future<void>.delayed(Duration.zero);
    await flushTerminalEngine(session.engine);

    expect(exportTerminalScrollback(session.engine), contains('hello'));
  });

  test('decodes pty output across utf8 chunk boundaries', () async {
    final handle = _FakeTransport();
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(handle);
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: Directory.systemTemp.path);
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final bytes = utf8.encode('café finished\r\n');
    // Split inside é (UTF-8 c3 a9).
    final split = bytes.indexOf(0xc3) + 1;
    handle.outputController
      ..add(Uint8List.fromList(bytes.take(split).toList()))
      ..add(Uint8List.fromList(bytes.skip(split).toList()));
    await Future<void>.delayed(Duration.zero);
    await flushTerminalEngine(session.engine);

    final text = exportTerminalScrollback(session.engine);
    expect(text, contains('café finished'));
    expect(text, isNot(contains('\uFFFD')));
  });

  test('pty output schedules viewport sync resize', () async {
    final handle = _FakeTransport();
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(handle);
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: Directory.systemTemp.path);
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    handle.resizeCalls.clear();

    // Resize viewport without immediate PTY sync so output path can sync later.
    session.onViewportResize(100, 40);
    expect(session.viewWidth, 100);
    expect(session.viewHeight, 40);

    handle.outputController.add(Uint8List.fromList(utf8.encode('draw\r\n')));
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(handle.resizeCalls, isNotEmpty);
    expect(handle.resizeCalls.last, (40, 100));
  });

  test(
    'wsl sessions do not pass UNC working directory to Windows pty',
    () async {
      if (!Platform.isWindows) return;
      String? capturedExecutable;
      String? capturedWorkingDirectory;
      List<String>? capturedArguments;
      final handle = _FakeTransport();
      final session = TerminalSession(
        executable:
            r'\\wsl.localhost\Ubuntu\home\hhoa\flashskyai\dist\flashskyai',
        transportStarter:
            (
              executable, {
              required arguments,
              required workingDirectory,
              required columns,
              required rows,
              environment,
            }) {
              capturedExecutable = executable;
              capturedArguments = List<String>.from(arguments);
              capturedWorkingDirectory = workingDirectory;
              return Future.value(handle);
            },
      );
      addTearDown(() async {
        session.dispose();
        await handle.outputController.close();
      });

      session.connect(
        workingDirectory: r'\\wsl.localhost\Ubuntu\home\hhoa\workspace',
      );
      session.onViewportResize(80, 24);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      if (capturedExecutable == 'wsl.exe') {
        expect(capturedWorkingDirectory, isNot(startsWith(r'\\wsl')));
        expect(
          capturedArguments,
          contains('/home/hhoa/flashskyai/dist/flashskyai'),
        );
      }
    },
  );

  test('single-slash wsl executable converts Windows workspace dir', () async {
    if (!Platform.isWindows) return;
    String? capturedExecutable;
    List<String>? capturedArguments;
    final handle = _FakeTransport();
    final session = TerminalSession(
      executable:
          r'\wsl.localhost\Ubuntu\home\hhoa\flashskai-ubuntu-wsl\dist\flashskyai',
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            capturedExecutable = executable;
            capturedArguments = List<String>.from(arguments);
            return Future.value(handle);
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: r'C:\Users\haung\git\teampilot\client');
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    if (capturedExecutable == 'wsl.exe') {
      expect(
        capturedArguments,
        contains('/home/hhoa/flashskai-ubuntu-wsl/dist/flashskyai'),
      );
    }
  });

  test('windows pty launch receives full environment for wsl.exe', () async {
    if (!Platform.isWindows) return;
    Map<String, String>? capturedEnvironment;
    final handle = _FakeTransport();
    final session = TerminalSession(
      executable:
          r'\wsl.localhost\Ubuntu\home\hhoa\flashskai-ubuntu-wsl\dist\flashskyai',
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            capturedEnvironment = environment == null
                ? null
                : Map<String, String>.from(environment);
            return Future.value(handle);
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(
      workingDirectory: r'C:\Users\haung\git\teampilot\client',
      extraEnvironment: const {'LLM_CONFIG_PATH': r'C:\config.json'},
    );
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(capturedEnvironment, isNotNull);
    expect(
      capturedEnvironment,
      containsPair('LLM_CONFIG_PATH', '/mnt/c/config.json'),
    );
    expect(capturedEnvironment!.keys, contains(anyOf('Path', 'PATH')));
    expect(
      capturedEnvironment!.keys,
      contains(anyOf('SystemRoot', 'windir', 'WINDIR')),
    );
  });

  group('connectWorkspaceShell validation', () {
    // Regression (new-terminal freeze): connectWorkspaceShell used to run the
    // sync CliExecutableValidator.validateLaunch, whose PATH lookup spawns
    // `where.exe` with Process.runSync on the UI thread. Under WSL
    // process-creation saturation that CreateProcess blocked the main isolate
    // for 20-60+ s. PATH validation now happens only in the launch
    // controller's async (isolate-backed) path; a WSL plan must reach the
    // transport starter without a synchronous lookup.
    test('wsl plan reaches transport without sync PATH lookup', () async {
      final handle = _FakeTransport();
      String? capturedExecutable;
      final session = TerminalSession(
        executable: 'wsl.exe',
        validateLaunch: true,
        transportStarter:
            (
              executable, {
              required arguments,
              required workingDirectory,
              required columns,
              required rows,
              environment,
            }) {
              capturedExecutable = executable;
              return Future.value(handle);
            },
      );
      addTearDown(() async {
        session.dispose();
        await handle.outputController.close();
      });

      session.connectWorkspaceShell(
        plan: WorkspaceShellLaunchPlan(
          executable: 'wsl.exe',
          arguments: const ['--exec', '/bin/zsh'],
          workingDirectory: '/home/user',
          useWslPaths: true,
          inheritHostEnvironment: true,
          runtimeTarget: RuntimeTarget.wsl('Ubuntu'),
          usesRemoteTransport: false,
        ),
      );
      session.onViewportResize(80, 24);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(capturedExecutable, 'wsl.exe');
      expect(session.isRunning, isTrue);
    });

    test('missing local absolute path fails fast without transport', () async {
      var transportStarted = false;
      final missing = Platform.isWindows
          ? r'C:\definitely\not\here\missing-cli.exe'
          : '/definitely/not/here/missing-cli';
      final session = TerminalSession(
        executable: missing,
        validateLaunch: true,
        transportStarter:
            (
              executable, {
              required arguments,
              required workingDirectory,
              required columns,
              required rows,
              environment,
            }) {
              transportStarted = true;
              return Future.value(_FakeTransport());
            },
      );
      addTearDown(session.dispose);

      session.connectWorkspaceShell(
        plan: WorkspaceShellLaunchPlan(
          executable: missing,
          arguments: const [],
          workingDirectory: Directory.systemTemp.path,
          useWslPaths: false,
          inheritHostEnvironment: true,
          runtimeTarget: RuntimeTarget.local(),
          usesRemoteTransport: false,
        ),
      );
      session.onViewportResize(80, 24);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(transportStarted, isFalse);
    });
  });

  group('spawn deadline', () {
    // Regression (WSL new-terminal spawn timeout): a single 15 s
    // startupDeadline used to cover the PTY spawn itself. WSL
    // process-creation saturation stalls `CreateProcessW` inside pty_create
    // for 20-70 s while the app stays responsive and the spawn still
    // succeeds, so the deadline killed launches that would have worked
    // ("Failed to start CLI: spawn timed out"). The spawn phase now gets
    // its own, much longer budget; startupDeadline only takes over once the
    // transport exists.
    WorkspaceShellLaunchPlan wslPlan() => WorkspaceShellLaunchPlan(
      executable: 'wsl.exe',
      arguments: const ['--exec', '/bin/zsh'],
      workingDirectory: '/home/user',
      useWslPaths: true,
      inheritHostEnvironment: true,
      runtimeTarget: RuntimeTarget.wsl('Ubuntu'),
      usesRemoteTransport: false,
    );

    TerminalSession spawnSession(
      Future<TerminalTransport> Function() spawn, {
      Duration spawnDeadline = const Duration(minutes: 3),
    }) => TerminalSession(
      executable: 'wsl.exe',
      validateLaunch: false,
      startupDeadline: const Duration(seconds: 15),
      spawnDeadline: spawnDeadline,
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) => spawn(),
    );

    test('slow spawn outlives startupDeadline and still starts', () {
      fakeAsync((async) {
        final handle = _FakeTransport();
        final spawn = Completer<TerminalTransport>();
        final session = spawnSession(() => spawn.future);
        String? failureMessage;
        session.connectWorkspaceShell(
          plan: wslPlan(),
          onProcessFailed: (message) => failureMessage = message,
        );
        session.onViewportResize(80, 24);

        // Past the old single 15 s deadline, before the spawn completes.
        async.elapse(const Duration(seconds: 30));
        expect(failureMessage, isNull, reason: 'spawn budget must exceed 15 s');
        expect(session.isConnecting, isTrue);

        spawn.complete(handle);
        async.elapse(const Duration(milliseconds: 200));
        expect(session.isRunning, isTrue);
        expect(failureMessage, isNull);

        session.dispose();
      });
    });

    test('spawn exceeding spawnDeadline fails and discards late transport', () {
      fakeAsync((async) {
        final handle = _FakeTransport();
        final spawn = Completer<TerminalTransport>();
        final session = spawnSession(
          () => spawn.future,
          spawnDeadline: const Duration(seconds: 5),
        );
        String? failureMessage;
        session.connectWorkspaceShell(
          plan: wslPlan(),
          onProcessFailed: (message) => failureMessage = message,
        );
        session.onViewportResize(80, 24);

        async.elapse(const Duration(seconds: 6));
        expect(failureMessage, contains('spawn timed out'));
        expect(session.isRunning, isFalse);

        // The spawn completing after the deadline must not resurrect the
        // failed session: the late transport is closed on arrival.
        spawn.complete(handle);
        async.elapse(const Duration(milliseconds: 200));
        expect(handle.closed, isTrue);
        expect(session.isRunning, isFalse);

        session.dispose();
      });
    });
  });

  group('linkProviders', () {
    TerminalSession makeSession() => TerminalSession(
      executable: _ptyTestExecutable,
      validateLaunch: false,
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) => Future.value(_FakeTransport()),
    );

    test('returns a UrlLinkProvider and a FilePathLinkProvider', () {
      final session = makeSession();
      addTearDown(session.dispose);

      final providers = session.linkProviders;
      expect(providers, hasLength(2));
      expect(providers[0], isA<UrlLinkProvider>());
      expect(providers[1], isA<FilePathLinkProvider>());
    });

    test('returns the same list instance on repeated access (lazy/cached)', () {
      final session = makeSession();
      addTearDown(session.dispose);

      final first = session.linkProviders;
      final second = session.linkProviders;
      expect(identical(first, second), isTrue);
    });

    test(
      'rebuilds file path link provider when connect assigns launch cwd',
      () {
        final session = makeSession();
        addTearDown(session.dispose);

        final stale = session.linkProviders;
        expect((stale[1] as FilePathLinkProvider).launchCwd, isEmpty);

        session.connect(workingDirectory: '/tmp/teampilot-link-cwd-test');

        final fresh = session.linkProviders;
        expect(identical(stale, fresh), isFalse);
        expect(
          (fresh[1] as FilePathLinkProvider).launchCwd,
          '/tmp/teampilot-link-cwd-test',
        );
      },
    );

    test('dispose clears and disposes the providers', () {
      final session = makeSession();

      // Force allocation before dispose.
      final providers = List<TerminalLinkProvider>.from(session.linkProviders);
      session.dispose();

      // A disposed ChangeNotifier throws FlutterError on addListener.
      for (final p in providers) {
        expect(() => p.addListener(() {}), throwsFlutterError);
      }
    });
  });
}
