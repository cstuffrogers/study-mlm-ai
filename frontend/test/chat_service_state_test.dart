// ChatService 请求状态测试：pending / error / retry 不依赖真实 WebSocket。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/services/chat_service.dart';

void main() {
  test('send 后进入 pending，retryLast 复用同一锚点重发', () {
    final svc = ChatService(dialogueId: 'unit-test');
    expect(svc.pending, false);
    expect(svc.lastError, isNull);

    // 不连接真实 WS：send 会尝试 connect()，这里只验证本地状态。
    svc.send(content: '请就这段导读展开释义', selectedText: '哲学基本问题');
    expect(svc.pending, true);
    expect(svc.lastQuestion, '请就这段导读展开释义');
    expect(svc.lastSelectedText, '哲学基本问题');
    expect(svc.turns.length, 1);

    // retryLast 会用同一锚点重发。
    final before = svc.turns.length;
    svc.retryLast();
    expect(svc.turns.length, before + 1);
    expect(svc.turns.last.selectedText, '哲学基本问题');
    expect(svc.pending, true);
    svc.dispose();
  });
}
