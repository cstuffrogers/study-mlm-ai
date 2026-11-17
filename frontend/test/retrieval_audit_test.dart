// 第三轮审计钉住的规则（都是本轮实测踩出来的，别再改回去）：
//
//  ① 非中文提问不该扫全库：本机语料全是中文原著，英文/纯数字只会在脚注
//     页码里蹭到命中，答案必然是噪声，而且以前要白扫 6 遍全库（600ms）。
//  ② 标准术语不能被单字虚词切碎：「实事求是」里的「是」是分隔符，
//     切完只剩「实事求」，检索再也拼不回来 → 术语整词另存一份。
//  ③ 相邻片段跨一个「的/之/是」要能拼回整词：「商品的价值」比
//     「商品」「价值」各命中一次更能证明这段在讲这件事。
//  ④ 定义型问句优先给定义句：问「国家的本质」要给
//     「国家是一个阶级压迫另一个阶级的机器」，不是「还没有进一步领悟到
//      国家的本质」这种顺带提及。
//  ⑤ 低覆盖提示只针对**主词**缺失：同义词别名不进分母，否则
//     「什么是实践」这种答得出来的问题也会被贴上「没有直接回答」。
//  ⑥ 缓存淘汰后不能有速度悬崖：连续几十个不同问题仍要百毫秒级。

import 'package:flutter_test/flutter_test.dart';

import 'package:marxism_reader/offline/local_dialogue.dart';
import 'package:marxism_reader/offline/offline_content.dart';

Future<String> _ask(String q, {String mode = 'explain'}) async {
  final r = await LocalDialogue.respond(
      dialogueId: 'audit-$q-$mode', content: q, mode: mode);
  final out = r['content'] ?? r['fallback'];
  return '$out';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await OfflineContent.ensureMeta();
    await OfflineContent.ensureChunks();
  });

  test('英文/纯数字提问不扫全库，直接说明本机只有中文原文', () async {
    await _ask('预热');
    for (final q in ['12345', 'abc', 'Marx']) {
      final sw = Stopwatch()..start();
      final out = await _ask(q);
      sw.stop();
      expect(out.contains('没匹配到可用依据'), isTrue,
          reason: '英文/纯数字不该在脚注页码里凑出一段「原文摘录」：$q');
      expect(sw.elapsedMilliseconds, lessThan(200),
          reason: '非中文提问不该扫全库（实测 118—520ms，现在是直接返回）');
    }
  });

  test('术语不被虚字切碎：「实事求是」要命中含这三个字的原文', () async {
    final out = await _ask('实事求是的思想路线');
    expect(out.contains('实事求是'), isTrue, reason: '被「是」切开就检不回来了');
    expect(out.contains('先说清楚'), isFalse,
        reason: '主词在正文里（实事求是），不该判成低覆盖');
  });

  test('跨「的」拼回整词：「商品的价值由什么决定」落到社会必要劳动时间', () async {
    final out = await _ask('商品的价值由什么决定');
    expect(out.contains('必要劳动'), isTrue,
        reason: '不拼整词时，讲贵金属的短段会顶到第一位；实际输出：$out');
  });

  test('定义型问句优先给定义句：「国家的本质」是国家机器', () async {
    final out = await _ask('国家的本质是什么');
    // 只看第一段引文（= 本次作答的依据）；第二段是补充引用，允许是「提及」句
    final first = out.split('\n\n').first;
    expect(first.contains('机器'), isTrue,
        reason: '「还没有进一步领悟到国家的本质」只是提及，不能当第一依据；实际：$first');
    expect(first.contains('犹太人'), isFalse,
        reason: '顺带提及的段落不能当定义题的第一依据；实际：$first');
    // 「原文这样界定」里必须是真定义句，不能拿提及句冒充
    final defBlock = out.contains('原文这样界定');
    if (defBlock) {
      expect(out.contains('领悟到国家的本质\n'), isFalse,
          reason: '标注为「界定」的引文必须是定义句；实际：$out');
    }
  });

  test('低覆盖提示只针对主词缺失：答得出来的问题不许贴提示', () async {
    for (final q in ['什么是实践', '什么是主要矛盾', '怎样做群众工作']) {
      final out = await _ask(q);
      expect(out.contains('先说清楚'), isFalse,
          reason: '$q 有明确原文依据，不该说「没有直接回答」');
      expect(out.contains('原文摘录'), isTrue);
    }
  });

  test('连续不同提问：缓存淘汰后仍在百毫秒级', () async {
    await _ask('预热');
    final times = <int>[];
    for (var i = 0; i < 24; i++) {
      final sw = Stopwatch()..start();
      await _ask('怎样理解${['实践', '矛盾', '国家', '群众', '真理', '自由'][i % 6]}'
          '${['标准', '形式', '问题', '过程', '关系', '地位', '原则', '内容'][i % 8]}');
      sw.stop();
      times.add(sw.elapsedMilliseconds);
    }
    times.sort();
    expect(times[(times.length * 9) ~/ 10], lessThan(500),
        reason: 'p90 超了说明某一轮又把全库扫了好几遍：$times');
  });
}
