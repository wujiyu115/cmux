import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/terminal/terminal_layout_presets.dart';
import 'package:teampilot/widgets/terminal/terminal_layout_toolbar.dart';

void main() {
  Future<AppLocalizations> pumpToolbar(
    WidgetTester tester, {
    VoidCallback? onSplitRight,
    VoidCallback? onSplitDown,
    ValueChanged<TerminalLayoutPreset>? onApplyPreset,
    VoidCallback? onEqualize,
    VoidCallback? onToggleZoom,
    VoidCallback? onShowCommandLog,
    void Function(Offset globalPosition)? onShowAgentSessions,
    bool isZoomed = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TerminalLayoutToolbar(
            onSplitRight: onSplitRight ?? () {},
            onSplitDown: onSplitDown ?? () {},
            onApplyPreset: onApplyPreset ?? (_) {},
            onEqualize: onEqualize ?? () {},
            onToggleZoom: onToggleZoom ?? () {},
            onShowCommandLog: onShowCommandLog ?? () {},
            onShowAgentSessions: onShowAgentSessions,
            isZoomed: isZoomed,
          ),
        ),
      ),
    );
    await tester.pump();
    return AppLocalizations.of(
      tester.element(find.byType(TerminalLayoutToolbar)),
    );
  }

  testWidgets('split right / down invoke their callbacks', (tester) async {
    var right = 0;
    var down = 0;
    final l10n = await pumpToolbar(
      tester,
      onSplitRight: () => right++,
      onSplitDown: () => down++,
    );

    await tester.tap(find.byTooltip(l10n.workspaceTerminalSplitRight));
    await tester.tap(find.byTooltip(l10n.workspaceTerminalSplitDown));
    expect(right, 1);
    expect(down, 1);
  });

  testWidgets('equalize and zoom invoke their callbacks', (tester) async {
    var equalize = 0;
    var zoom = 0;
    final l10n = await pumpToolbar(
      tester,
      onEqualize: () => equalize++,
      onToggleZoom: () => zoom++,
    );

    await tester.tap(find.byTooltip(l10n.workspaceTerminalEqualize));
    await tester.tap(find.byTooltip(l10n.workspaceTerminalZoomPane));
    expect(equalize, 1);
    expect(zoom, 1);
  });

  testWidgets('zoom icon reflects isZoomed', (tester) async {
    await pumpToolbar(tester, isZoomed: false);
    expect(find.byIcon(Icons.zoom_out_map), findsOneWidget);
    expect(find.byIcon(Icons.zoom_in_map), findsNothing);

    await pumpToolbar(tester, isZoomed: true);
    expect(find.byIcon(Icons.zoom_in_map), findsOneWidget);
    expect(find.byIcon(Icons.zoom_out_map), findsNothing);
  });

  testWidgets('command log button invokes its callback', (tester) async {
    var opened = 0;
    final l10n = await pumpToolbar(
      tester,
      onShowCommandLog: () => opened++,
    );

    await tester.tap(find.byTooltip(l10n.workspaceTerminalCommandLog));
    expect(opened, 1);
  });

  testWidgets('agent sessions button reports its anchor position', (
    tester,
  ) async {
    final positions = <Offset>[];
    final l10n = await pumpToolbar(
      tester,
      onShowAgentSessions: positions.add,
    );

    await tester.tap(find.byTooltip(l10n.workspaceTerminalResumeSessions));
    await tester.pump();

    expect(positions, hasLength(1));
    expect(positions.single.dx, greaterThan(0));
    expect(positions.single.dy, greaterThan(0));
  });

  testWidgets('agent sessions button hides without a callback', (
    tester,
  ) async {
    final l10n = await pumpToolbar(tester);
    expect(find.byTooltip(l10n.workspaceTerminalResumeSessions), findsNothing);
  });

  testWidgets('preset menu emits the chosen preset enum', (tester) async {
    final chosen = <TerminalLayoutPreset>[];
    final l10n = await pumpToolbar(
      tester,
      onApplyPreset: chosen.add,
    );

    await tester.tap(find.byTooltip(l10n.workspaceTerminalLayout));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.workspaceTerminalLayoutGrid));
    await tester.pumpAndSettle();

    expect(chosen, [TerminalLayoutPreset.grid2x2]);
  });
}
