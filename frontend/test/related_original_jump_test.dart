// 「相关原文」跳转回归测试。
//
// 锁住三件事：
//   1. 单条相关原文 → 直接打开原书阅读器，并翻到该分片所在页（不是弹一两句片段）；
//   2. 多条相关原文 → 先给列表（著作 · 位置 + 摘录），点任一条同样定位到正文；
//   3. 从浮动会话窗点「相关原文」时，会话窗先撤下（它在 Overlay 里会压住原文页），
//      读完返回后会话窗自动恢复——层级问题不再出现。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marxism_reader/models/message.dart';
import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'package:marxism_reader/screens/work_reader_screen.dart';
import 'package:marxism_reader/services/chat_service.dart';
import 'package:marxism_reader/theme/app_theme.dart';
import 'package:marxism_reader/widgets/floating_chat.dart';
import 'package:marxism_reader/widgets/related_original_button.dart';
import 'helpers/offline_assets_guard.dart';

/// 取《大众哲学》中段的一个真实 L1 分片（保证不在首页，能验证「定位」确实生效）。
Map<String, dynamic> _midChunk() {
  final list = OfflineContent.chunksOfWork('大众哲学')
      .where((c) => (c['layer'] as num?)?.toInt() == 1)
      .toList();
  return list[list.length ~/ 2];
}

String _head(String text, [int n = 14]) {
  final t = text.replaceAll('\n', '').replaceAll('\r', '').trim();
  return t.length > n ? t.substring(0, n) : t;
}

class _Host extends StatefulWidget {
  final List<String> ids;
  final List<String> turnChunks;
  final bool withChat;
  const _Host({required this.ids, this.turnChunks = const [], this.withChat = false});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  OverlayEntry? _entry;

  // 与 chapter_guide_screen / work_reader_screen 里同一套浮窗挂载逻辑。
  void _openChat() {
    if (_entry != null) return;
    final overlay = Overlay.of(context);
    final size = MediaQuery.of(context).size;
    final w = (size.width - 64).clamp(280.0, 372.0);
    final h = (size.height * 0.62).clamp(300.0, 560.0);
    final turns = [
      ChatTurn(role: 'user', content: '这条怎么说？'),
      ChatTurn(role: 'ai', content: '……', sourceChunks: widget.turnChunks),
    ];
    final entry = OverlayEntry(
      builder: (_) => FloatingChat(
        turns: turns,
        status: '本机模式',
        currentMode: ChatMode.explain,
        criticalReading: false,
        onModeChanged: (_) {},
        onToggleCritical: () {},
        onSend: (_) {},
        onClear: () {},
        onClose: _closeChat,
        onOpenOriginal: _openRelatedOriginal,
        initialOffset: Offset(size.width - w - 16, 96),
        bounds: size,
        size: Size(w, h),
      ),
    );
    overlay.insert(entry);
    _entry = entry;
    setState(() {});
  }

  void _closeChat() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  Future<void> _openRelatedOriginal(List<String> ids) async {
    final nav = Navigator.of(context, rootNavigator: true);
    _closeChat();
    await showRelatedOriginalsFrom(nav, ids);
    if (!mounted) return;
    _openChat();
  }

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ElevatedButton(
            onPressed: () => openOriginalAt(context, widget.ids.first),
            child: const Text('打开原文'),
          ),
          ElevatedButton(
            onPressed: () => showRelatedOriginals(context, widget.ids),
            child: const Text('打开列表'),
          ),
          if (widget.withChat)
            ElevatedButton(onPressed: _openChat, child: const Text('开会话')),
        ]),
      ),
    );
  }
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(MaterialApp(theme: AppTheme.build(), home: home));
  await tester.pumpAndSettle();
}

void main() {
  if (skipWithoutOfflineAssets()) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb.ensure();
    await OfflineContent.ensureMeta();
    await OfflineContent.ensureChunks();
  });

  testWidgets('单条相关原文直接进阅读器并定位到该分片所在页', (tester) async {
    final chunk = _midChunk();
    final id = '${chunk['id']}';
    final head = _head('${chunk['text']}');
    await _pump(tester, _Host(ids: [id]));

    await tester.tap(find.text('打开原文'));
    await tester.pumpAndSettle();

    expect(find.byType(WorkReaderScreen), findsOneWidget);
    // 关键：当前页就是该分片正文（而不是第一页 / 上次进度）
    expect(find.textContaining(head), findsWidgets);
  });

  testWidgets('多条相关原文：先列著作·位置，点一条跳到正文位置', (tester) async {
    final list = OfflineContent.chunksOfWork('大众哲学')
        .where((c) => (c['layer'] as num?)?.toInt() == 1)
        .toList();
    final a = list[list.length ~/ 4];
    final b = list[list.length ~/ 2];
    await _pump(tester, _Host(ids: ['${a['id']}', '${b['id']}']));

    await tester.tap(find.text('打开列表'));
    await tester.pumpAndSettle();

    expect(find.byType(RelatedOriginalsScreen), findsOneWidget);
    expect(find.textContaining('大众哲学'), findsWidgets);
    expect(find.text('跳到原文'), findsNWidgets(2));

    // 点第二条 → 定位到第二条分片的正文
    await tester.tap(find.text('跳到原文').last);
    await tester.pumpAndSettle();
    expect(find.byType(WorkReaderScreen), findsOneWidget);
    expect(find.textContaining(_head('${b['text']}')), findsWidgets);
  });

  testWidgets('浮窗里点相关原文：先撤浮窗再开原文，返回后浮窗恢复', (tester) async {
    final chunk = _midChunk();
    final id = '${chunk['id']}';
    await _pump(tester, _Host(ids: [id], turnChunks: [id], withChat: true));

    await tester.tap(find.text('开会话'));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingChat), findsOneWidget);

    await tester.tap(find.text('相关原文'));
    await tester.pumpAndSettle();

    // 原文页在，浮窗已撤（不会再压住原文）
    expect(find.byType(WorkReaderScreen), findsOneWidget);
    expect(find.byType(FloatingChat), findsNothing);
    expect(find.textContaining(_head('${chunk['text']}')), findsWidgets);

    // 返回后浮窗自动恢复，对话内容没丢
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(FloatingChat), findsOneWidget);
    expect(find.text('这条怎么说？'), findsOneWidget);
  });
}
