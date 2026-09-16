import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/pairing_client_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/pairing/pairing_remote_dir_browser_page.dart';
import 'package:teampilot/repositories/pairing_settings_repository.dart';
import 'package:teampilot/services/pairing/pairing_client.dart';
import 'package:teampilot/theme/app_theme.dart';

/// Answers `fs.browse` from a scripted map of path → listing, so the page can be
/// driven through a whole navigation session without a desktop.
///
/// A null key is the page's opening call (`path == null`); a `null` entry means
/// the fake host has nothing there, which is how a refused listing is staged.
class _ScriptedCubit extends PairingClientCubit {
  _ScriptedCubit(this.listings)
      : super(settings: InMemoryPairingSettingsRepository());

  final Map<String?, PairingDirListing> listings;

  /// Every path the page asked for, in order — null for the opening call.
  final List<String?> requested = [];

  @override
  Future<PairingCallResult<PairingDirListing>> browseDir({
    String? path,
    String? targetId,
  }) async {
    requested.add(path);
    final listing = listings[path];
    if (listing == null) {
      return const PairingCallResult.failed('no such folder');
    }
    return PairingCallResult.ok(listing);
  }
}

/// One Windows machine: its drive roots ride along on every listing.
const _roots = [r'C:\', r'D:\'];

/// The opening listing on a Windows host: the default workspace root on C:.
const _opening = PairingDirListing(
  path: r'C:\Users\me\Documents\TeamPilot',
  parent: r'C:\Users\me\Documents',
  dirs: ['proj'],
  roots: _roots,
);

void main() {
  late _ScriptedCubit cubit;
  String? popped;

  tearDown(() => cubit.close());

  Future<void> open(
    WidgetTester tester,
    Map<String?, PairingDirListing> listings,
  ) async {
    cubit = _ScriptedCubit(listings);
    popped = null;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildDarkTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  popped = await showPairingRemoteDirBrowser(context, cubit);
                },
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

  testWidgets('lists the Windows drive roots alongside the folders',
      (tester) async {
    await open(tester, {null: _opening});

    expect(find.text(r'C:\'), findsOneWidget);
    expect(find.text(r'D:\'), findsOneWidget);
    expect(find.text('proj'), findsOneWidget);
    // The drive the listing sits on is marked, so the block reads as a position
    // rather than a row of buttons.
    expect(find.text('Current'), findsOneWidget);
  });

  testWidgets('entering a drive root lists it', (tester) async {
    await open(tester, {
      null: _opening,
      r'D:\': const PairingDirListing(
        path: r'D:\',
        parent: null,
        dirs: ['code', 'games'],
        roots: _roots,
      ),
    });

    await tester.tap(find.text(r'D:\'));
    await tester.pumpAndSettle();

    expect(cubit.requested, [null, r'D:\']);
    expect(find.text('code'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
  });

  testWidgets('a drive root with no parent can still reach the drives block',
      (tester) async {
    // The host reports a drive root as its own parent, so a listing that stops
    // there has no parent row of its own. Without the extra row the drives are
    // unreachable and the user is stuck on whichever volume they entered.
    await open(tester, {
      null: _opening,
      r'D:\': const PairingDirListing(
        path: r'D:\',
        parent: null,
        dirs: [],
        roots: _roots,
      ),
    });

    await tester.tap(find.text(r'D:\'));
    await tester.pumpAndSettle();
    expect(find.text('Parent directory'), findsOneWidget);

    await tester.tap(find.text('Parent directory'));
    await tester.pumpAndSettle();
    expect(cubit.requested.last, isNull);
    expect(find.text('proj'), findsOneWidget);
  });

  testWidgets('a machine with no drives shows no drives block', (tester) async {
    // POSIX hosts, and every remote target: nothing to jump to, and no stray
    // label implying otherwise.
    await open(tester, {
      null: const PairingDirListing(
        path: '/home/me',
        parent: '/home',
        dirs: ['code'],
      ),
    });

    expect(find.text('code'), findsOneWidget);
    expect(find.text('Current'), findsNothing);
    expect(find.text('/home/me'), findsOneWidget);
  });

  testWidgets('offers to select the folder being listed', (tester) async {
    await open(tester, {null: _opening});

    await tester.tap(find.text('Select this folder'));
    await tester.pumpAndSettle();

    expect(popped, r'C:\Users\me\Documents\TeamPilot');
  });

  testWidgets('a failed jump keeps the previous listing and says why',
      (tester) async {
    // A blocked drive (BitLocker, an unplugged volume) must not blank the page.
    await open(tester, {null: _opening});

    await tester.tap(find.text(r'D:\'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not list this folder.'), findsOneWidget);
    expect(find.text('proj'), findsOneWidget);
  });
}