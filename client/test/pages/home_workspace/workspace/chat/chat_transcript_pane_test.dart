import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/home_workspace/workspace/chat/chat_transcript_pane.dart';
import 'package:teampilot/services/chat/chat_transcript_row.dart';

Widget _host(
  ValueListenable<ChatTranscriptSnapshot> transcript, {
  ValueChanged<String>? onSend,
  bool canSend = true,
}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(
    body: ChatTranscriptPane(
      transcript: transcript,
      canSend: canSend,
      onSend: onSend ?? (_) {},
    ),
  ),
);

ChatTranscriptSnapshot _snapshot(List<ChatTranscriptRow> rows) =>
    ChatTranscriptSnapshot(rows: rows, family: 'claude', sessionId: 's1');

void main() {
  testWidgets('renders prompt, answer, and tool rows', (tester) async {
    final transcript = ValueNotifier(
      _snapshot([
        const ChatTranscriptRow(
          id: 'u1#text',
          kind: ChatTranscriptRowKind.user,
          text: 'run the tests',
        ),
        const ChatTranscriptRow(
          id: 'm1#text',
          kind: ChatTranscriptRowKind.assistant,
          text: 'Running them now.',
        ),
        const ChatTranscriptRow(
          id: 'm1#tool:t1',
          kind: ChatTranscriptRowKind.tool,
          toolName: 'Bash',
          detail: 'flutter test',
        ),
      ]),
    );
    addTearDown(transcript.dispose);

    await tester.pumpWidget(_host(transcript));

    expect(find.text('run the tests'), findsOneWidget);
    expect(find.text('Running them now.'), findsOneWidget);
    expect(find.text('Bash  flutter test'), findsOneWidget);
  });

  testWidgets('a tool row expands to its output', (tester) async {
    final transcript = ValueNotifier(
      _snapshot([
        const ChatTranscriptRow(
          id: 'm1#tool:t1',
          kind: ChatTranscriptRowKind.tool,
          toolName: 'Bash',
          detail: 'flutter test',
          text: 'All tests passed!',
        ),
      ]),
    );
    addTearDown(transcript.dispose);

    await tester.pumpWidget(_host(transcript));
    expect(find.text('All tests passed!'), findsNothing);

    await tester.tap(find.text('Bash  flutter test'));
    await tester.pump();

    expect(find.text('All tests passed!'), findsOneWidget);
  });

  testWidgets('the composer sends the prompt and clears itself', (
    tester,
  ) async {
    final sent = <String>[];
    final transcript = ValueNotifier(_snapshot(const []));
    addTearDown(transcript.dispose);

    await tester.pumpWidget(_host(transcript, onSend: sent.add));

    await tester.enterText(find.byType(TextField), '  hello agent  ');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(sent, ['hello agent']);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '',
    );
  });

  testWidgets('a disabled composer drops the prompt instead of sending', (
    tester,
  ) async {
    final sent = <String>[];
    final transcript = ValueNotifier(_snapshot(const []));
    addTearDown(transcript.dispose);

    await tester.pumpWidget(
      _host(transcript, onSend: sent.add, canSend: false),
    );
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(sent, isEmpty);
  });

  testWidgets('each unavailable state explains itself', (tester) async {
    final cases = {
      ChatTranscriptUnavailable.noDirectory:
          'Open a terminal in a folder first.',
      ChatTranscriptUnavailable.noSessionFile:
          'No agent session recorded for this folder yet. Start one in the '
          'terminal.',
      ChatTranscriptUnavailable.readFailed:
          'Could not read the session '
          'transcript.',
    };
    for (final entry in cases.entries) {
      final transcript = ValueNotifier(
        ChatTranscriptSnapshot(unavailable: entry.key),
      );
      await tester.pumpWidget(_host(transcript));
      expect(find.text(entry.value), findsOneWidget);
      transcript.dispose();
    }
  });

  testWidgets('no agent session disables the composer and says why', (
    tester,
  ) async {
    final sent = <String>[];
    final transcript = ValueNotifier(
      const ChatTranscriptSnapshot(
        unavailable: ChatTranscriptUnavailable.noSessionFile,
      ),
    );
    addTearDown(transcript.dispose);

    await tester.pumpWidget(_host(transcript, onSend: sent.add));

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
    expect(
      find.text('Start the agent in the terminal first, then message it here.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    expect(sent, isEmpty, reason: 'a prompt with nowhere to land is dropped');
  });

  testWidgets('new rows follow the reader only at the bottom', (tester) async {
    final rows = [
      for (var i = 0; i < 40; i++)
        ChatTranscriptRow(
          id: 'm$i#text',
          kind: ChatTranscriptRowKind.assistant,
          text: 'answer $i',
        ),
    ];
    final transcript = ValueNotifier(_snapshot(rows));
    addTearDown(transcript.dispose);

    await tester.pumpWidget(_host(transcript));
    await tester.pump();

    // Scrolled away from the bottom: a new row must not yank the view.
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    final offsetBefore = tester
        .widget<ListView>(find.byType(ListView))
        .controller!
        .offset;

    transcript.value = _snapshot([
      ...rows,
      const ChatTranscriptRow(
        id: 'm99#text',
        kind: ChatTranscriptRowKind.assistant,
        text: 'answer 99',
      ),
    ]);
    await tester.pumpAndSettle();

    final offsetAfter = tester
        .widget<ListView>(find.byType(ListView))
        .controller!
        .offset;
    expect(offsetAfter, offsetBefore);
  });
}
