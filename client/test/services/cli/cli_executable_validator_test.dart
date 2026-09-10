import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cli_executable_validator.dart';

void main() {
  group('CliExecutableValidator.validateLaunch (sync)', () {
    // Regression: the sync PATH lookup spawned `where.exe` via
    // Process.runSync on the UI thread; under WSL process-creation
    // saturation that CreateProcess blocked the main isolate for 20-60+ s
    // (new-terminal freeze). WSL invocations must skip it, matching
    // validateLaunchPathLookupAsync.
    test('wsl.exe skips the PATH lookup', () {
      final error = CliExecutableValidator.validateLaunch(
        executable: 'wsl.exe',
        workingDirectory: '/home/user',
      );
      expect(error, isNull);
    });

    test('wsl UNC invocation skips the PATH lookup', () {
      final error = CliExecutableValidator.validateLaunch(
        executable: r'\\wsl.localhost\Ubuntu\home\user\bin\tool',
        workingDirectory: r'\\wsl.localhost\Ubuntu\home\user',
      );
      expect(error, isNull);
    }, skip: !Platform.isWindows);

    test('missing absolute path still fails fast', () {
      final missing = Platform.isWindows
          ? r'C:\definitely\not\here\missing-cli.exe'
          : '/definitely/not/here/missing-cli';
      final error = CliExecutableValidator.validateLaunch(
        executable: missing,
        workingDirectory: Directory.systemTemp.path,
      );
      expect(error, isNotNull);
    });
  });
}
