import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/pairing_client_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/pairing/pairing_new_workspace_sheet.dart';
import 'package:teampilot/repositories/pairing_settings_repository.dart';
import 'package:teampilot/services/pairing/pairing_client.dart';

const _local = PairingTarget(
  id: 'local',
  label: 'This device',
  kind: 'local',
);
const _wsl = PairingTarget(
  id: 'wsl:Ubuntu',
  label: 'WSL · Ubuntu',
  kind: 'wsl',
);

/// Records what the sheet asked of the pairing channel without a live host: the
/// sheet's contract is which targetId it forwards, not what the desktop does.
class _RecordingCubit extends PairingClientCubit {
  _RecordingCubit() : super(settings: InMemoryPairingSettingsRepository());

  /// The only directory the fake host offers, so a browse always lands here.
  static const browsePath = '/home/me';

  final List<String?> browseTargetIds = [];
  final List<(String folderPath, String? targetId)> created = [];

  @override
  Future<PairingCallResult<PairingDirListing>> browseDir({
    String? path,
    String? targetId,
  }) async {
    browseTargetIds.add(targetId);
    return const PairingCallResult.ok(
      PairingDirListing(path: browsePath, parent: null, dirs: []),
    );
  }

  @override
  Future<PairingCallResult<String>> createWorkspace({
    required String folderPath,
    String? title,
    String? groupId,
    String? targetId,
  }) async {
    created.add((folderPath, targetId));
    return const PairingCallResult.ok('ws-new');
  }
}

void main() {
  late _RecordingCubit cubit;

  setUp(() => cubit = _RecordingCubit());
  tearDown(() => cubit.close());

  /// Mounts a screen whose only job is to open the sheet, since the sheet is a
  /// modal route and needs a Navigator above it.
  Future<void> openSheet(
    WidgetTester tester, {
    required List<PairingTarget> targets,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showPairingNewWorkspaceSheet(
                  context,
                  cubit,
                  const [],
                  targets,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Walks the real browse flow: the sheet pushes a full-screen browser page, so
  /// a folder is only chosen once that page pops with it.
  Future<void> pickFolder(WidgetTester tester) async {
    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select this folder'));
    await tester.pumpAndSettle();
  }

  testWidgets('hides the machine picker when the desktop advertised none',
      (tester) async {
    // A desktop that predates machine selection. The phone must not offer a
    // choice it cannot make, and must send no targetId at all.
    await openSheet(tester, targets: const []);

    expect(find.text('Machine'), findsNothing);

    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();
    expect(cubit.browseTargetIds, [null]);
  });

  testWidgets('hides the machine picker when only one machine exists',
      (tester) async {
    // The host always lists itself, so one entry is not "no data" — it is
    // "nothing to choose", and a one-option dropdown is pure noise.
    await openSheet(tester, targets: const [_local]);

    expect(find.text('Machine'), findsNothing);
  });

  testWidgets('shows the machine picker once there is a choice', (tester) async {
    await openSheet(tester, targets: const [_local, _wsl]);

    expect(find.text('Machine'), findsOneWidget);
    // Host-rendered label, shown verbatim rather than localized.
    expect(find.text('This device'), findsOneWidget);
  });

  testWidgets('browses on the machine the picker defaults to', (tester) async {
    await openSheet(tester, targets: const [_local, _wsl]);

    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();
    expect(cubit.browseTargetIds, ['local']);
  });

  testWidgets('switching machines drops the folder picked on the old one',
      (tester) async {
    // Not a courtesy: a path names nothing on another machine, and the host
    // cannot tell ('/home/me' is plausible everywhere). Clearing it is what
    // keeps the path/target pair coherent.
    await openSheet(tester, targets: const [_local, _wsl]);

    await pickFolder(tester);
    expect(find.text('/home/me'), findsOneWidget);

    await tester.tap(find.text('This device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WSL · Ubuntu').last);
    await tester.pumpAndSettle();

    // Folder back to the placeholder, and the name it seeded is gone too.
    expect(find.text('/home/me'), findsNothing);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('submits the chosen machine with the folder', (tester) async {
    await openSheet(tester, targets: const [_local, _wsl]);

    await tester.tap(find.text('This device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WSL · Ubuntu').last);
    await tester.pumpAndSettle();

    await pickFolder(tester);
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(cubit.browseTargetIds, ['wsl:Ubuntu']);
    expect(cubit.created, [('/home/me', 'wsl:Ubuntu')]);
  });
}
