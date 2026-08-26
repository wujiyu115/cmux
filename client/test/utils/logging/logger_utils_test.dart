import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/logging/logger_utils.dart';

Future<String> _readLogWhenContains(String path, String needle) async {
  final file = File(path);
  for (var attempt = 0; attempt < 40; attempt++) {
    if (await file.exists()) {
      final contents = await file.readAsString();
      if (contents.contains(needle)) return contents;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  if (!await file.exists()) return '';
  return file.readAsString();
}

void main() {
  test('initFileLogging creates app log under app data root', () async {
    final temp = await Directory.systemTemp.createTemp('tp_logs_');
    addTearDown(() async {
      try {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      } on Object {
        // Log file may still be open on Windows.
      }
    });

    // File logging is opt-in now, so `initFileLogging` alone is a no-op.
    await AppLogger.instance.setFileLoggingEnabled(true, appDataRoot: temp.path);
    addTearDown(
      () => AppLogger.instance.setFileLoggingEnabled(
        false,
        appDataRoot: temp.path,
      ),
    );
    AppLogger.instance.i('hello from test');
    AppLogger.instance.d('trace from test');
    await AppLogger.instance.flushFileLogging();

    final logDir = Directory('${temp.path}/logs');
    expect(await logDir.exists(), isTrue);

    final logPath = AppLogger.instance.currentLogFilePath;
    expect(logPath, isNotNull);

    final files = await AppLogger.instance.listLogFiles();
    expect(files, isNotEmpty);
    expect(files.first, logPath);

    final contents = await _readLogWhenContains(logPath!, 'hello from test');
    expect(contents, contains('hello from test'));
    expect(contents, contains('trace from test'));
    expect(
      contents,
      matches(
        RegExp(
          r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} \|  INFO \d+ \| [^\|]+\.dart:\d+:\d+ \| hello from test',
        ),
      ),
    );
  });
  test('nothing reaches disk while file logging is off', () async {
    // The opt-in gate sits before the pending buffer, so an app running with the
    // switch off neither writes nor silently queues for a later flush.
    final temp = await Directory.systemTemp.createTemp('tp_logs_off_');
    addTearDown(() async {
      try {
        if (await temp.exists()) await temp.delete(recursive: true);
      } on Object {
        // Windows may still hold a handle.
      }
    });

    await AppLogger.instance.setFileLoggingEnabled(
      false,
      appDataRoot: temp.path,
    );
    final before = AppLogger.instance.pendingLogCount;
    AppLogger.instance.i('must not be persisted');
    await AppLogger.instance.initFileLogging(temp.path);

    expect(AppLogger.instance.fileLoggingEnabled, isFalse);
    expect(AppLogger.instance.getFileLoggerInitialized(), isFalse);
    expect(
      AppLogger.instance.pendingLogCount,
      before,
      reason: 'the line was dropped, not queued',
    );
    expect(await Directory('${temp.path}/logs').exists(), isFalse);
  });

  test('turning it off closes the sink but stays reversible', () async {
    final temp = await Directory.systemTemp.createTemp('tp_logs_toggle_');
    addTearDown(() async {
      try {
        if (await temp.exists()) await temp.delete(recursive: true);
      } on Object {
        // Windows may still hold a handle.
      }
    });

    await AppLogger.instance.setFileLoggingEnabled(true, appDataRoot: temp.path);
    expect(AppLogger.instance.fileLoggingEnabled, isTrue);

    await AppLogger.instance.setFileLoggingEnabled(
      false,
      appDataRoot: temp.path,
    );
    expect(AppLogger.instance.fileLoggingEnabled, isFalse);
    expect(AppLogger.instance.currentLogFilePath, isNull);

    // A storage failure latches a separate flag; a user opt-in must still work.
    await AppLogger.instance.setFileLoggingEnabled(true, appDataRoot: temp.path);
    expect(AppLogger.instance.fileLoggingEnabled, isTrue);
    expect(AppLogger.instance.currentLogFilePath, isNotNull);

    await AppLogger.instance.setFileLoggingEnabled(
      false,
      appDataRoot: temp.path,
    );
  });
}
