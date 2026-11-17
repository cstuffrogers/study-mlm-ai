// 使用说明 & 本机数据页 —— 内容门禁。
//
// 用户明确要求两件事：
//  ① 每种对话模式的介绍要写进使用说明（不能只写在代码注释里）；
//  ② 更新后数据不能变（说明里必须讲清楚「升级不丢」与「什么情况会丢」）。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/models/message.dart';
import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_store_keys.dart';
import 'package:marxism_reader/screens/data_backup_screen.dart';
import 'package:marxism_reader/theme/app_theme.dart';
import 'package:marxism_reader/widgets/guide_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpGuide(WidgetTester t) async {
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.build(),
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showUsageGuide(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LocalDb.reloadForTest();
  });

  // 原有用例（前序版本加的）：批判性阅读按钮的说明不能从引导里消失。
  // 本节因新增「五种对话模式」而顺延为第五节，断言同步。
testWidgets('引导说明包含批判性阅读按钮的位置/开启方式/作用/关闭方式',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) => ElevatedButton(
          onPressed: () => showUsageGuide(ctx),
          child: const Text('打开引导'),
        )),
      ),
    ));
    await tester.tap(find.text('打开引导'));
    await tester.pumpAndSettle();

    expect(find.text('软件使用说明'), findsOneWidget);
    // 有专门一节
    expect(find.text('五、对话浮窗里的「批判性阅读」按钮　【重点】'), findsOneWidget);
    // 位置、状态、生效时机、批判姿态标记、与辩难的区别、关闭方式
    expect(find.textContaining('顶部标题栏'), findsOneWidget);
    expect(find.textContaining('红色高亮为「开」'), findsOneWidget);
    expect(find.textContaining('再发送的问题才会'), findsOneWidget);
    expect(find.textContaining('【批判对象·非借鉴】'), findsOneWidget);
    expect(find.textContaining('与「辩难」模式的区别'), findsOneWidget);
    expect(find.textContaining('再点一次按钮关掉'), findsOneWidget);
    // 配置一节也说明真实模型为何会回退 Mock，避免用户误判为「没配上」
    expect(find.textContaining('关闭思维链'), findsOneWidget);
    // 新口径：只保留「相关原文」按钮，不教用户认分片编号
    expect(find.textContaining('不显示任何内部编号'), findsOneWidget);
    expect(find.textContaining('相关原文'), findsWidgets);
    expect(find.textContaining('CH-ME-TH-02-1'), findsNothing);
    expect(find.textContaining('带下划线的可点'), findsNothing);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('使用说明列出了五种模式，且逐条说明「会给什么」', (t) async {
    await t.binding.setSurfaceSize(const Size(900, 2400));
    await _pumpGuide(t);

    expect(find.textContaining('五种对话模式各给什么'), findsOneWidget);

    // 每种模式的名字都要出现
    for (final m in ChatMode.values) {
      expect(find.textContaining('${m.label}：'), findsOneWidget,
          reason: '使用说明缺「${m.label}」的介绍');
    }
    // 介绍内容取自引擎自述，抽查两条关键差异
    expect(find.textContaining('逐字引文当依据'), findsOneWidget);
    expect(find.textContaining('只提问不给答案'), findsOneWidget);
    expect(find.textContaining('什么时候用哪个'), findsOneWidget);

    await t.binding.setSurfaceSize(null);
  });

  testWidgets('使用说明讲清了升级不丢数据 / 什么情况会丢', (t) async {
    await t.binding.setSurfaceSize(const Size(900, 2600));
    await _pumpGuide(t);

    expect(find.textContaining('升级与数据保留'), findsOneWidget);
    expect(find.textContaining('覆盖安装新版本不会清空本机数据'), findsOneWidget);
    expect(find.textContaining('卸载重装'), findsOneWidget);
    expect(find.textContaining('API Key 出于安全不进备份'), findsOneWidget);
    // 列举的数据面必须覆盖用户点名的几项
    for (final k in ['对话记录', '学习记录', '学情', '原文笔记', '阅读进度', '大模型 API 设置']) {
      expect(find.textContaining(k), findsWidgets, reason: '说明里漏了「$k」');
    }

    await t.binding.setSurfaceSize(null);
  });

  testWidgets('本机数据页：显示现有数据量并说明备份口径', (t) async {
    SharedPreferences.setMockInitialValues({
      LocalStoreKeys.dialogues: jsonEncode({
        'd-1': {
          'id': 'd-1',
          'title': 't',
          'current_mode': 'explain',
          'created_at': '2026-01-01T00:00:00',
          'messages': [
            {'role': 'user', 'content': 'q', 'mode': 'explain'},
            {'role': 'ai', 'content': 'a', 'mode': 'explain'},
          ],
        },
      }),
      LocalStoreKeys.attempts: jsonEncode([
        {'item_id': 'q_a01', 'is_correct': true},
      ]),
      LocalStoreKeys.reader('《资本论（第一卷）》', LocalStoreKeys.readerNotes):
          jsonEncode([
        {'para': 1, 'text': 'note'},
      ]),
    });
    LocalDb.reloadForTest();
    await LocalDb.ensure();

    await t.binding.setSurfaceSize(const Size(900, 1600));
    await t.pumpWidget(MaterialApp(theme: AppTheme.build(), home: const DataBackupScreen()));
    await t.pumpAndSettle();

    expect(find.text('本机数据'), findsOneWidget);
    expect(find.textContaining('对话 1'), findsOneWidget);
    expect(find.textContaining('消息 2'), findsOneWidget);
    expect(find.textContaining('答题记录 1'), findsOneWidget);
    expect(find.textContaining('原文笔记 1'), findsOneWidget);
    expect(find.textContaining('复制备份'), findsOneWidget);
    expect(find.textContaining('从剪贴板恢复'), findsOneWidget);
    expect(find.textContaining('API Key 不进备份'), findsOneWidget);

    await t.binding.setSurfaceSize(null);
  });
}
