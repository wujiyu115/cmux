import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/repositories/command_mru_repository.dart';
import 'package:teampilot/services/commands/command_catalog.dart';
import 'package:teampilot/services/commands/command_ids.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  const path = '/data/command-mru.json';

  CommandMruRepository repo() => CommandMruRepository(fs: fs, path: path);

  setUp(() {
    fs = InMemoryFilesystem();
  });

  test('missing file loads as empty', () async {
    expect(await repo().load(), isEmpty);
  });

  test('touch then load round-trips a single id', () async {
    await repo().touch(CommandIds.showCheatsheet);
    expect(await repo().load(), [CommandIds.showCheatsheet]);
  });

  test('touch moves an existing id to the front', () async {
    final r = repo();
    await r.touch(CommandIds.showCheatsheet);
    await r.touch(CommandIds.commandPalette);
    await r.touch(CommandIds.showCheatsheet);

    expect(await r.load(), [
      CommandIds.showCheatsheet,
      CommandIds.commandPalette,
    ]);
  });

  test('touch dedupes so an id appears once', () async {
    final r = repo();
    await r.touch(CommandIds.zoomIn);
    await r.touch(CommandIds.zoomIn);

    expect(await r.load(), [CommandIds.zoomIn]);
  });

  test('touch caps the retained list', () async {
    final r = repo();
    final ids = [for (final def in CommandCatalog.v1) def.id];
    expect(ids.length, greaterThan(CommandMruRepository.cap));

    for (final id in ids) {
      await r.touch(id);
    }

    final loaded = await r.load();
    expect(loaded.length, CommandMruRepository.cap);
    // Most recent (last touched) is at the front.
    expect(loaded.first, ids.last);
  });

  test('load drops ids not in the catalog', () async {
    // Persist a valid id then a garbage one via touch of a real id, then
    // hand-write a mixed file.
    fs.files[path] =
        '{"version":1,"data":{"ids":["not.a.real.command","${CommandIds.zoomIn}"]}}';

    expect(await repo().load(), [CommandIds.zoomIn]);
  });

  test('corrupt file loads as empty and never throws', () async {
    fs.files[path] = 'not json at all }{';

    expect(await repo().load(), isEmpty);
  });
}
