import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/models/layout_preferences.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;

  setUp(() {
    fs = InMemoryFilesystem();
  });

  Future<EditorCubit> openCubit(EditorAutoSaveMode mode) async {
    final cubit = EditorCubit(fs: fs, autoSaveMode: () => mode);
    await fs.writeString('/repo/a.txt', 'initial');
    await cubit.openFile('w1', '/repo/a.txt');
    return cubit;
  }

  test('afterDelay saves 1s after the edit', () async {
    final cubit = await openCubit(EditorAutoSaveMode.afterDelay);
    addTearDown(cubit.close);
    final controller = cubit.controllerFor('w1', '/repo/a.txt')!;

    controller.text = 'edited';
    expect(cubit.state.bucket('w1').dirtyPaths, contains('/repo/a.txt'));

    // Timer not fired yet.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(cubit.state.bucket('w1').dirtyPaths, isNotEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(cubit.state.bucket('w1').dirtyPaths, isEmpty);
    expect(await fs.readString('/repo/a.txt'), 'edited');
  });

  test('default (no resolver) never auto-saves', () async {
    final cubit = await openCubit(EditorAutoSaveMode.off);
    addTearDown(cubit.close);
    cubit.controllerFor('w1', '/repo/a.txt')!.text = 'edited';

    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(cubit.state.bucket('w1').dirtyPaths, isNotEmpty);
    expect(await fs.readString('/repo/a.txt'), 'initial');
  });

  test('focusChange saves via maybeSaveOnBlur only when dirty', () async {
    final cubit = await openCubit(EditorAutoSaveMode.focusChange);
    addTearDown(cubit.close);

    // Clean buffer: blur does nothing.
    cubit.maybeSaveOnBlur('w1', '/repo/a.txt');
    expect(await fs.readString('/repo/a.txt'), 'initial');

    cubit.controllerFor('w1', '/repo/a.txt')!.text = 'edited';
    cubit.maybeSaveOnBlur('w1', '/repo/a.txt');
    await Future<void>.delayed(Duration.zero); // saveFile is async.
    expect(cubit.state.bucket('w1').dirtyPaths, isEmpty);
    expect(await fs.readString('/repo/a.txt'), 'edited');
  });

  test('afterDelay timer is cancelled when the file closes', () async {
    final cubit = await openCubit(EditorAutoSaveMode.afterDelay);
    cubit.controllerFor('w1', '/repo/a.txt')!.text = 'edited';
    expect(cubit.closeFile('w1', '/repo/a.txt', force: true), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(await fs.readString('/repo/a.txt'), 'initial');
    await cubit.close();
  });
}
