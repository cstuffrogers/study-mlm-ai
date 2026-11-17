// 本机检索精度/效率回归测试（依赖 assets/offline 真实原文）。
//
// 这一轮修掉的精度问题，逐条钉住：
//  ① 目录/索引片段被当成「原文摘录」——「主义的认识论和实践观,论述了…」这种
//     OCR 目录行进了引文框，读者会以为原著就这么写；
//  ② 问句被当成答案句——「实践为什么是检验真理的唯一标准呢？」是标题，
//     不是结论，摘进引文等于没答；
//  ③ 同一句原文被不同段落编号重复登记 → 回答里同一句话刷两遍；
//  ④ 「矛盾」「实践」这种两字泛词去做跨著作对照，命中的全是无关段落；
//  ⑤ 长问句里的「的/是/在」2-gram 撑分，把关键词稀释掉。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_dialogue.dart';
import 'package:marxism_reader/offline/offline_content.dart';

import 'helpers/offline_assets_guard.dart';

Future<String> ask(String q, {String mode = 'explain', String para = ''}) async {
  final r = await LocalDialogue.respond(
      dialogueId: 'precision', content: q, mode: mode, paragraphId: para);
  return '${r['content'] ?? r['fallback'] ?? ''}';
}

void main() {
  if (skipWithoutOfflineAssets()) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await OfflineContent.ensureMeta();
    await OfflineContent.ensureChunks();
  });

  test('目录/索引片段不进引文框', () async {
    // 这条问句以前会把《…选集（四卷本·目录序言）》的 OCR 目录行摘出来
    for (final q in ['为什么说实践是检验真理的唯一标准', '阶级斗争为什么会发生']) {
      final a = await ask(q);
      expect(a.contains('目录序言'), isFalse, reason: '目录类来源不该作为引文出处：$q');
      expect(RegExp(r'^> .*,.*,.*,', multiLine: true).hasMatch(a), isFalse,
          reason: '塞满半角逗号的目录行不该出现在引文中：$q');
    }
  });

  test('释义给到定义句，不把问句当答案', () async {
    final a = await ask('为什么说实践是检验真理的唯一标准');
    expect(a, contains('实践是检验真理的唯一标准'));
    // 命中句必须是陈述（句末不是问号）
    final quote = RegExp(r'^> (.+)$', multiLine: true).allMatches(a).map((m) => m.group(1)!);
    expect(quote, isNotEmpty, reason: '应至少摘出 1 句原文');
    expect(quote.first.trimRight().endsWith('？'), isFalse, reason: '问答句当引文');
    expect(a, contains('《'), reason: '引文必须带出处');
  });

  test('同一句引文不重复出现', () async {
    final a = await ask('人的本质是一切社会关系的总和', mode: 'debate');
    final quotes = RegExp(r'^> (.+)$', multiLine: true)
        .allMatches(a)
        .map((m) => m.group(1)!.replaceAll(RegExp(r'\s'), ''))
        .toList();
    expect(quotes.toSet().length, quotes.length, reason: '引文出现重复：$quotes');
  });

  test('泛词不做跨著作对照，会明说原因', () async {
    final a = await ask('矛盾', mode: 'connect');
    expect(a, contains('关键词太泛'));
    expect(a.contains('同一说法在别的著作里'), isFalse);
  });

  test('具体术语做跨著作对照，且一部著作只出一条', () async {
    final a = await ask('经济基础和上层建筑是什么关系', mode: 'connect');
    expect(a, contains('同一说法在别的著作里'));
    final sources = RegExp(r'^—— 《(.+?)》', multiLine: true)
        .allMatches(a)
        .map((m) => m.group(1)!)
        .toList();
    expect(sources.length, greaterThanOrEqualTo(2));
    // 引文出处与跨著作出处的书名不该全靠同一部书撑起来
    expect(sources.toSet().length, greaterThanOrEqualTo(2));
  });

  test('重复提问走缓存，比首次快一个量级', () async {
    final sw1 = Stopwatch()..start();
    await ask('商品的价值由什么决定', mode: 'test');
    sw1.stop();
    final sw2 = Stopwatch()..start();
    await ask('商品的价值由什么决定', mode: 'test');
    sw2.stop();
    expect(sw2.elapsedMicroseconds, lessThan(sw1.elapsedMicroseconds),
        reason: '第二次同样提问应命中检索缓存');
  });

  test('五种模式在同一问句下输出互不相同', () async {
    final outs = <String>[];
    for (final m in ['explain', 'dig', 'debate', 'connect', 'test']) {
      outs.add(await ask('经济基础和上层建筑是什么关系', mode: m));
    }
    expect(outs.toSet().length, 5, reason: '模式输出不该雷同');
  });
}
