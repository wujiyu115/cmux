import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat/tab_member_materializer.dart';
import 'package:teampilot/cubits/chat/tab_session_runtime_coordinator.dart';
import 'package:teampilot/models/app_session.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test(
    'personal materialize hangs until markMemberReady when shell not running',
    () async {
      final store = ChatTabStore();
      store.setActiveWorkspace('ws-1');
      final tab = ChatTab(
        info: const ChatTabInfo(id: 'sess-1', title: 't', subtitle: ''),
        workspaceId: 'ws-1',
        cliTeamName: '',
      )..persistedSession = AppSession(
          sessionId: 'sess-1',
          workspaceId: 'ws-1',
          createdAt: 0,
        );
      store.append(tab);

      final materializer = TabMemberMaterializer(
        runtime: TabSessionRuntimeCoordinator(
          tabStore: store,
          isClosed: () => false,
        ),
        tabStore: store,
        isClosed: () => false,
      );

      final pending = materializer.materializeMember('sess-1', 'sess-1', '');
      var completed = false;
      unawaited(pending.then((_) => completed = true));
      // Yield so materialize can park on the ready completer without wall delay.
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      materializer.markMemberReady('sess-1', 'sess-1');
      await pending;
      expect(completed, isTrue);
    },
  );
}
