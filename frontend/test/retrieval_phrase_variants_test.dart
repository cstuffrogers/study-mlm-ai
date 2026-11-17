// 本机检索：同一个词的两种写法（带不带「的」）+ 词块回退的回归测试。
//
// 这一轮修掉的问题，逐条钉住：
//  ① 库里写「主要的矛盾」，用户写「主要矛盾」→ 逐字比对一条都找不到，
//     《矛盾论》整章被漏掉，答案反而来自《论列宁主义基础》的顺带一提；
//  ② 检索用变体写法命中了段落，摘句却只认原写法 → 检索到了也摘不出引文；
//  ③ 「反对本本主义」在库里没有整块字面，回退只取首3/尾3 得到「本主义」，
//     半个词命中的全是泛段，真正的《反对本本主义》反而排不上；
//  ④ 「主要矛盾」曾被单字虚词「要」切成「矛盾」，只剩泛词去检索；
//  ⑤ 编者注/版本说明冒充作者原话。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_dialogue.dart';
import 'package:marxism_reader/offline/offline_content.dart';

import 'helpers/offline_assets_guard.dart';

Future<String> ask(String q, {String mode = 'explain'}) async {
  final r = await LocalDialogue.respond(
      dialogueId: 'variants', content: q, mode: mode);
  return '${r['content'] ?? r['fallback'] ?? ''}';
}

Iterable<String> quotesOf(String a) =>
    RegExp(r'^> (.+)$', multiLine: true).allMatches(a).map((m) => m.group(1)!);

Iterable<String> sourcesOf(String a) =>
    RegExp(r'^—— 《(.+?)》', multiLine: true).allMatches(a).map((m) => m.group(1)!);

void main() {
  if (skipWithoutOfflineAssets()) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await OfflineContent.ensureMeta();
    await OfflineContent.ensureChunks();
  });

  test('带不带「的」都要能检到：《主要矛盾》→《矛盾论》', () async {
    final a = await ask('什么是主要矛盾');
    final q = quotesOf(a).toList();
    expect(q, isNotEmpty, reason: '「什么是主要矛盾」必须摘出原文');
    expect(q.first, contains('主要的矛盾'), reason: '库里的写法是「主要的矛盾」');
    expect(sourcesOf(a).first, contains('矛盾论'));
  });

  test('词块回退要落到实词尾巴上：《反对本本主义》', () async {
    final a = await ask('为什么要反对本本主义');
    expect(sourcesOf(a), contains('反对本本主义'),
        reason: '问的就是这本书，出处必须是它自己');
    expect(quotesOf(a).join(), contains('本本主义'));
  });

  test('「辩证否定观」回退到「辩证的否定」', () async {
    final a = await ask('什么是辩证否定观');
    final all = quotesOf(a).join();
    expect(all, contains('辩证的否定'), reason: '库里写作「辩证的否定」');
  });

  test('「国家的本质」给到国家机器这个界定，不是顺带提及', () async {
    final a = await ask('国家的本质是什么');
    final all = quotesOf(a).join();
    expect(all, contains('机器'), reason: '国家是阶级压迫的机器');
  });

  test('多词问句不能只命中一个泛词就作答', () async {
    final a = await ask('社会主义初级阶段的主要矛盾是什么');
    final q = quotesOf(a).toList();
    if (q.isEmpty) {
      // 允许「库里没有」的老实话，但不许空手而归还装作答了
      expect(a, contains('先说清楚'));
    } else {
      expect(q.first, contains('矛盾'));
    }
  });

  test('编者注/版本说明不进引文', () async {
    for (final q in ['什么是实践', '商品的价值由什么决定']) {
      for (final one in quotesOf(await ask(q))) {
        expect(one.trimLeft().startsWith('注：'), isFalse, reason: q);
        expect(RegExp(r'^\[\d{1,3}\]').hasMatch(one.trimLeft()), isFalse,
            reason: '脚注注码不是原文：$q');
      }
    }
  });

  test('热态单次提问在 600ms 内（全库 2.3 万段）', () async {
    await ask('什么是人民民主专政'); // 预热：加载资产 + 建索引
    final sw = Stopwatch()..start();
    final a = await ask('什么是国家的本质');
    sw.stop();
    expect(a, isNotEmpty);
    expect(sw.elapsedMilliseconds, lessThan(600),
        reason: '探针扫描 + 候选集比对应该在这个量级');
  });
}
