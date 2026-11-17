// 本机检索：这一轮「回答内容不对 / 排序不对」的回归测试。
//
// 逐条钉住（每条都对应一个实测踩过的坑）：
//  ① 「对」被当词首虚词剥掉 →「对象」变「象」，问「中国革命的对象是谁」
//      检索词成了「中国革命的象」，权威那本《中国革命和中国共产党》排不上；
//  ② 探针先扫泛词、凑够 60 个候选就收手 →「社会主义初级阶段」这种稀有整词
//      一次都没扫到，同时含两个词、覆盖率 1.0 的段永远进不了候选集；
//  ③ 低覆盖提示拿「词表第一个词」判断 → 术语整词是插在词表头部的，于是
//      库里根本没有的概念（社会主义初级阶段）被误判成「答出来了」；
//  ④ 「整句加分」（含「什么是」）只有复述问话的引子段能命中 →《马克思的
//      经济学说》里「什么是商品的价值？这个问题是我们必须解答的」被顶到第一；
//  ⑤ 定义题只压权不筛选 →「还没有进一步领悟到国家的本质」（提及句）照样当依据；
//  ⑥ 定义题摘句只认「就是/是指」→ 纯「是」的界定句不加分，摘到前面那句碎片
//      （「生产力的增长的现象。」），真正的界定句排在后面；
//  ⑦ 主语前有「的/之」的段（「帝国主义的主要矛盾」）被当成主题句加分。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_dialogue.dart';
import 'package:marxism_reader/offline/offline_content.dart';

import 'helpers/offline_assets_guard.dart';

Future<String> ask(String q, {String mode = 'explain'}) async {
  final r = await LocalDialogue.respond(
      dialogueId: 'content-fix', content: q, mode: mode);
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

  test('「对象」不被剥成「象」：问中国革命的对象，出处必须是那本原著', () async {
    final a = await ask('中国革命的对象是谁');
    expect(quotesOf(a), isNotEmpty, reason: '必须摘出原文');
    expect(sourcesOf(a).first, contains('中国革命和中国共产党'),
        reason: '库里专门有「第二节 中国革命的对象」一节');
  });

  test('稀有整词先扫：库里没有「社会主义初级阶段」要如实说明', () async {
    final a = await ask('什么是社会主义初级阶段');
    expect(a, contains('先说清楚'),
        reason: '语料里只有「感性认识是认识的初级阶段」，没有社会主义初级阶段，'
            '不能拿「资产阶级的社会主义」冒充答案');
  });

  test('整句加分不能奖励「复述问话」的引子段', () async {
    final a = await ask('什么是商品的价值');
    final q = quotesOf(a).join();
    expect(q, isNot(contains('必须解答')),
        reason: '「什么是商品的价值？这个问题是我们必须解答的」是引子，不是答案');
    expect(q, contains('价值'));
  });

  test('定义题只给界定句：提及句不当依据', () async {
    final a = await ask('国家的本质是什么');
    final q = quotesOf(a).join();
    expect(q, contains('国家是一个阶级压迫另一个阶级的机器'));
    expect(sourcesOf(a).join(), isNot(contains('神圣家族')),
        reason: '「还没有进一步领悟到国家的本质」只是提到这个词');
  });

  test('定义题摘句钉住界定句，不摘前面的碎片', () async {
    final a = await ask('什么是阶级');
    expect(quotesOf(a).join(), contains('阶级是一个历史的范畴'));
  });

  test('主语前有「的」的段不算主题句：《主要矛盾》仍落《矛盾论》', () async {
    final a = await ask('什么是主要矛盾');
    expect(quotesOf(a).first, contains('主要的矛盾'));
    expect(sourcesOf(a).first, contains('矛盾论'),
        reason: '「帝国主义的主要矛盾」是帝国主义的下属议题，不是主题句');
  });

  test('探针零命中要收手，但不能提前收手到空结果', () async {
    final a = await ask('什么是实践？旧唯物主义不懂实践');
    expect(quotesOf(a), isNotEmpty);
    expect(a, isNot(contains('先说清楚')));
  });
}
