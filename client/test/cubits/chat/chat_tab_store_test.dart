import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';

ChatTab _tab(String id) => ChatTab(
  info: ChatTabInfo(id: id, title: id, subtitle: ''),
);

void main() {
  test('append + activeTabBySessionId + activeTabInfos', () {
    final store = ChatTabStore();
    store.append(_tab('a'));
    store.append(_tab('b'));

    expect(store.activeTabCount, 2);
    expect(store.activeTabInfos().map((i) => i.id).toList(), ['a', 'b']);
  });

  test('activeTab clamps index', () {
    final store = ChatTabStore()
      ..append(_tab('a'))
      ..append(_tab('b'));
    expect(store.activeTab(99)!.info.id, 'b');
    expect(store.activeTab(-1)!.info.id, 'a');
  });

}
