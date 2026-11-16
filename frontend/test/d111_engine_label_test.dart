// D111 门禁：本机/在线引擎标签必须能让用户分辨「没配 Key」与「配了但调用失败」。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/models/message.dart';
import 'package:marxism_reader/services/chat_service.dart';
import 'package:marxism_reader/widgets/floating_chat.dart';
import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_dialogue.dart';
import 'package:marxism_reader/offline/offline_content.dart';

ChatTurn _ai(String engine, {String note = ''}) => ChatTurn(
      role: 'ai',
      content: '原文摘录……',
      engine: engine,
      engineNote: note,
    );

Widget _host(ChatTurn turn) => MaterialApp(
      home: Scaffold(
        body: Stack(children: [FloatingChat(
          turns: [turn],
          status: '本机模式',
          currentMode: ChatMode.explain,
          criticalReading: false,
          onModeChanged: (_) {},
          onToggleCritical: () {},
          onSend: (_) {},
          onClear: () {},
          onClose: () {},
          initialOffset: Offset.zero,
          bounds: const Size(1280, 900),
          size: const Size(360, 520),
        )]),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('未配置 Key：标签说明回答是原文摘录', (t) async {
    await t.binding.setSurfaceSize(const Size(1280, 900));
    await t.pumpWidget(_host(_ai('local', note: 'not-configured')));
    expect(find.textContaining('未配置 API Key'), findsOneWidget);
    expect(find.textContaining('原文摘录'), findsWidgets);
  });

  testWidgets('在线模型调用失败：把原因显示出来', (t) async {
    await t.pumpWidget(_host(_ai('local', note: 'failed:HTTP 401 密钥无效')));
    expect(find.textContaining('在线模型失败'), findsOneWidget);
    expect(find.textContaining('HTTP 401'), findsOneWidget);
  });

  testWidgets('模型返回空正文：单独文案', (t) async {
    await t.pumpWidget(_host(_ai('local', note: 'empty-reply')));
    expect(find.textContaining('返回空正文'), findsOneWidget);
  });

  testWidgets('在线模型成功：显示模型名', (t) async {
    await t.pumpWidget(_host(_ai('cloud:qwen-plus')));
    expect(find.textContaining('在线模型 · qwen-plus'), findsOneWidget);
  });

  test('ChatTurn 默认 engineNote 为空，旧记录不受影响', () {
    expect(ChatTurn(role: 'ai', content: 'x').engineNote, '');
  });

  test('未配置 Key 时本机引擎回答带上 engine_note=not-configured', () async {
    await OfflineContent.ensureMeta();
    await LocalDb.resetAll();
    LocalDb.routeId = 'route_A';
    final r = await LocalDialogue.respond(
      content: '什么是实践？',
      mode: 'explain',
      criticalReading: false,
      dialogueId: 'd111-probe',
    );
    expect(r['type'], 'ai_message');
    expect(r['engine'], 'local');
    expect(r['engine_note'], 'not-configured');
  });
}
