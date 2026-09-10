import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/file_tree_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';
import 'package:teampilot/widgets/right_tools/file_tree_panel.dart';
import 'package:teampilot/widgets/right_tools/right_tools_lifecycle.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/test_runtime_context.dart';

/// 60 rows × 36px extent ≈ 2160px of content — comfortably scrollable in the
/// default 800×600 test surface.
InMemoryFilesystem _fs({int fileCount = 60}) {
  final fs = InMemoryFilesystem();
  fs.ensureDir('/repo');
  for (var i = 0; i < fileCount; i++) {
    fs.files['/repo/file$i.txt'] = 'x';
  }
  return fs;
}

Future<FileTreeCubit> _warmCubit(InMemoryFilesystem fs) async {
  final cubit = FileTreeCubit(fs: fs);
  await cubit.setRoot('/repo');
  return cubit;
}

Widget _host(FileTreeCubit cubit, WorkbenchCubit workbench) {
  final theme = ThemeData(useMaterial3: true);
  return TpTheme(
    data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: theme,
      home: Scaffold(
        body: BlocProvider<WorkbenchCubit>.value(
          value: workbench,
          child: RightToolsLifecycle(
            data: RightToolsLifecycleData(
              scope: const WorkspaceToolsScopeState(resolving: true),
              fileTreeCubit: cubit,
              pokeOnTurnEnd: () {},
              ensureFileTreeReady: () {},
            ),
            child: FileTreePanel(
              cubit: cubit,
              workContext: testRuntimeContext('/repo'),
              workspaceId: 'w1',
            ),
          ),
        ),
      ),
    ),
  );
}

/// The vertical list controller, reached through the [Scrollable] the
/// [ListView] builds (the panel owns the controller internally).
ScrollController _listController(WidgetTester tester) {
  final scrollable = find.descendant(
    of: find.byType(ListView),
    matching: find.byType(Scrollable),
  );
  return tester.widget<Scrollable>(scrollable).controller!;
}

/// Wheel-scrolls the tree list by [ticks] notches (120px each). Rows are
/// wrapped in file-drag sources that claim mouse drags, so the wheel is the
/// list's actual scroll gesture.
Future<void> _wheelScroll(WidgetTester tester, int ticks) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      position: tester.getCenter(find.byType(ListView)),
      scrollDelta: Offset(0, 120.0 * ticks),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('restores the retained scroll offset on remount', (
    tester,
  ) async {
    final cubit = await _warmCubit(_fs());
    final workbench = WorkbenchCubit();
    cubit.setListScrollOffset(300);

    await tester.pumpWidget(_host(cubit, workbench));
    // Frame 2 mounts the staggered list; the restore runs post-frame after it.
    await tester.pump();
    await tester.pump();

    expect(_listController(tester).offset, 300);
    await cubit.close();
    await workbench.close();
  });

  testWidgets('records the scrolled offset for a later remount', (
    tester,
  ) async {
    final cubit = await _warmCubit(_fs());
    final workbench = WorkbenchCubit();
    expect(cubit.retainedListScrollOffset, 0);

    await tester.pumpWidget(_host(cubit, workbench));
    await tester.pump();
    await tester.pump();

    await _wheelScroll(tester, 2);
    expect(cubit.retainedListScrollOffset, 240);

    // A fresh panel (new State, new ScrollController) lands back at 240.
    await tester.pumpWidget(_host(cubit, workbench));
    await tester.pump();
    await tester.pump();
    expect(_listController(tester).offset, 240);
    await cubit.close();
    await workbench.close();
  });

  testWidgets('clamps the restore to the available content', (tester) async {
    // 8 rows ≈ 288px: far less than the retained 300px offset.
    final cubit = await _warmCubit(_fs(fileCount: 8));
    final workbench = WorkbenchCubit();
    cubit.setListScrollOffset(300);

    await tester.pumpWidget(_host(cubit, workbench));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final controller = _listController(tester);
    expect(controller.offset, controller.position.maxScrollExtent);
    expect(controller.offset, lessThan(300));
    await cubit.close();
    await workbench.close();
  });
}
