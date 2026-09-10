import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/repositories/layout_repository.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('layout cubit persists preferences', () async {
    final cubit = LayoutCubit(
      repository: LayoutRepository(await SharedPreferences.getInstance()),
    );
    await cubit.load();

    await cubit.setThemeMode('dark');
    expect(cubit.state.preferences.themeMode, 'dark');
  });

  test('setEditorPreviewTabs persists and reloads', () async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = LayoutCubit(repository: LayoutRepository(prefs));
    await cubit.load();

    await cubit.setEditorPreviewTabs(false);
    expect(cubit.state.preferences.editorPreviewTabs, isFalse);

    final reloaded = LayoutCubit(repository: LayoutRepository(prefs));
    await reloaded.load();
    expect(reloaded.state.preferences.editorPreviewTabs, isFalse);
  });
}
