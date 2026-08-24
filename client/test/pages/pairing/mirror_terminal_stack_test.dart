import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/pairing/mirror_terminal_stack.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'the terminal gets the full width even while the selection chip is empty',
    (tester) async {
      final engine = TerminalEngine(config: TerminalConfig.defaults());
      addTearDown(engine.dispose);

      // The mirror page's shape: a column whose cross axis is loose, so a
      // shrink-wrapping stack here reports zero width and the terminal's grid
      // falls to the 8-column floor.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const SizedBox(height: 48),
                Expanded(
                  child: MirrorTerminalStack(
                    terminal: TerminalView(engine),
                    // No selection is live: the chip is a zero-size box.
                    overlay: const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(TerminalView));
      expect(
        size.width,
        tester.view.physicalSize.width / tester.view.devicePixelRatio,
      );
      expect(size.height, greaterThan(0));
    },
  );
}
