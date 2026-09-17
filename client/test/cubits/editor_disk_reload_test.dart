import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/services/io/filesystem.dart';

import '../support/in_memory_filesystem.dart';

/// [InMemoryFilesystem] plus a hand-driven [FsWatcher] event stream.
class _WatchableInMemoryFilesystem extends InMemoryFilesystem
    implements FsWatcher {
  final _events = StreamController<FsChangeEvent>.broadcast();

  void emit(String path, FsChangeType type) {
    if (!_events.isClosed) _events.add(FsChangeEvent(path: path, type: type));
  }

  @override
  FsTreeWatch watchTree(String path) => FsTreeWatch(
    events: _events.stream,
    close: () async {},
  );
}

void main() {
  late _WatchableInMemoryFilesystem fs;
  late EditorCubit cubit;

  setUp(() {
    fs = _WatchableInMemoryFilesystem();
    cubit = EditorCubit(fs: fs);
  });

  tearDown(() async {
    await cubit.close();
  });

  Future<void> openDirtyCleanFile() async {
    await fs.writeString('/repo/a.txt', 'old content');
    await cubit.openFile('w1', '/repo/a.txt');
  }

  test('external modify reloads a clean buffer', () async {
    await openDirtyCleanFile();
    final controller = cubit.controllerFor('w1', '/repo/a.txt')!;
    expect(controller.text, 'old content');

    await fs.writeString('/repo/a.txt', 'new content');
    fs.emit('/repo/a.txt', FsChangeType.modified);
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(controller.text, 'new content');
    expect(cubit.state.bucket('w1').dirtyPaths, isEmpty);
  });

  test('external modify leaves a dirty buffer untouched', () async {
    await openDirtyCleanFile();
    final controller = cubit.controllerFor('w1', '/repo/a.txt')!;
    controller.text = 'user edits';

    await fs.writeString('/repo/a.txt', 'new content');
    fs.emit('/repo/a.txt', FsChangeType.modified);
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(controller.text, 'user edits');
    expect(cubit.state.bucket('w1').dirtyPaths, contains('/repo/a.txt'));
  });

  test('events for other files are ignored', () async {
    await openDirtyCleanFile();
    final controller = cubit.controllerFor('w1', '/repo/a.txt')!;

    await fs.writeString('/repo/b.txt', 'other');
    fs.emit('/repo/b.txt', FsChangeType.modified);
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(controller.text, 'old content');
  });

  test('delete events do not clear the buffer', () async {
    await openDirtyCleanFile();
    final controller = cubit.controllerFor('w1', '/repo/a.txt')!;

    fs.emit('/repo/a.txt', FsChangeType.deleted);
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(controller.text, 'old content');
  });

  test('closing the tab disposes the watch without errors', () async {
    await openDirtyCleanFile();
    expect(cubit.closeFile('w1', '/repo/a.txt', force: true), isTrue);

    // Late event after close must be a no-op.
    fs.emit('/repo/a.txt', FsChangeType.modified);
    await Future<void>.delayed(const Duration(milliseconds: 700));
  });

  test('burst of events coalesces into one reload', () async {
    await openDirtyCleanFile();

    await fs.writeString('/repo/a.txt', 'final');
    fs.emit('/repo/a.txt', FsChangeType.modified);
    fs.emit('/repo/a.txt', FsChangeType.modified);
    fs.emit('/repo/a.txt', FsChangeType.modified);
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(cubit.controllerFor('w1', '/repo/a.txt')!.text, 'final');
  });
}
