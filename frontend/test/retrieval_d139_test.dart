// D139：单机版 LocalDialogue 五模式回答质量门禁。
//
// 逐条钉住这一轮实测踩到的坑（每条都对应一次真实的错答）：
//  ① 检索词去噪顺序：`_questionNoise` 里长整块必须排在短整块前面，
//     「如何理解矛盾的普遍性与特殊性」先切「如何理解」再切「如何」，
//     否则切出「理解矛盾/理解」把真正主词「矛盾」稀释，首条依据跑到
//     1844 年手稿（首条打分 13.4），而不是《矛盾论》；
//  ② 覆盖率判定要看前 3 段 + 选区逐字重合：只比首段、只比单一主语时，
//     用户选中原文再问会一路报「没有直接回答这个问题」的假警报；
//  ③ 引文只认原文层（layer==1）：提纲类章节的 layer2/3/4 是命题概括、
//     术语注释、哲学解析，挂着「逐字引用」印出来等于替编者代言；
//  ④ 问句不是依据句：教材把小标题写成问句（「实践为什么是检验真理的
//     唯一标准呢？」），整段只有这一句时以前照样被当成原文摘出来；
//  ⑤ 关键词必须是整词：被切坏的碎片（「段原文展开」「理解矛盾」）不能当
//     主语，否则覆盖率判定永远失败、假警报常驻；
//  ⑥ 句子里没有实词时要说「请点名」，不要从库里捞两段不相干的话冒充依据。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_dialogue.dart';
import 'package:marxism_reader/offline/offline_content.dart';

import 'helpers/offline_assets_guard.dart';

Future<String> ask(String q, {String mode = 'explain', String sel = ''}) async {
  final r = await LocalDialogue.respond(
      dialogueId: 'd139', content: q, mode: mode, selectedText: sel);
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

  test('① 长整块先切：「如何理解矛盾的普遍性与特殊性」主语是矛盾，落《矛盾论》',
      () async {
    final a = await ask('如何理解矛盾的普遍性与特殊性？');
    expect(sourcesOf(a), isNotEmpty, reason: '必须摘出原文');
    expect(sourcesOf(a).first, contains('矛盾论'),
        reason: '去噪顺序错了会切出「理解矛盾」，首条依据跑到 1844 年手稿');
    expect(a, isNot(contains('理解矛盾')), reason: '提问动词不是检索词');
    expect(a, isNot(contains('没有直接回答这个问题')),
        reason: '命中了《矛盾论》还报「没有直接回答」就是假警报');
  });

  test('② 选中原文再问不报假警报：前 3 段 + 选区逐字重合都算命中', () async {
    const sel = '从前的一切唯物主义（包括费尔巴哈的唯物主义）的主要缺点是：'
        '对事物、现实、感性，只是从客体的或者直观的形式去理解，'
        '而不是把它们当作感性的人的活动，当作实践去理解，不是从主观方面去理解。';
    final a = await ask('请就这段原文展开', sel: sel);
    expect(a, isNot(contains('没有直接回答这个问题')),
        reason: '选中的正是《提纲》第一条，库里必有原文');
    expect(a, isNot(contains('段原文展开')), reason: '指令词不是关键词');
    expect(a, isNot(contains('理解矛盾')), reason: '指令碎片不是关键词');
  });

  test('③ 引文只取原文层：命题概括/术语注释/解析不得挂「逐字引用」', () async {
    for (final q in ['什么是实践', '实践为什么是检验真理的唯一标准']) {
      final a = await ask(q);
      for (final qq in quotesOf(a)) {
        expect(qq, isNot(contains('【术语】')), reason: '$q：注疏被当原文摘出');
        expect(qq, isNot(contains('【语境】')), reason: '$q：注疏被当原文摘出');
        expect(qq, isNot(contains('【哲学意义】')), reason: '$q：注疏被当原文摘出');
      }
      expect(sourcesOf(a), isNot(contains(predicate<String>((s) => s.contains('正典')))),
          reason: '$q：注疏层不能当主证');
    }
  });

  test('④ 问句不当依据句', () async {
    final a = await ask('实践为什么是检验真理的唯一标准');
    final qs = quotesOf(a).toList();
    expect(qs, isNotEmpty);
    for (final q in qs) {
      expect(q.trim().endsWith('？'), isFalse,
          reason: '「实践为什么是检验真理的唯一标准呢？」是教材小标题，不是答案');
    }
  });

  test('⑤ 无实词就问用户点名，不能拿不相干的原文冒充依据', () async {
    final a = await ask('这段话什么意思');
    expect(a, contains('【先定位】'));
    expect(quotesOf(a), isEmpty, reason: '没实词就不该有引文');
  });

  test('⑥ 概念词典没收的长概念如实说「先说清楚」，不能拿短词顶替', () async {
    final a = await ask('什么是社会主义初级阶段');
    expect(a, contains('先说清楚'),
        reason: '库里只有「社会主义」，没有「社会主义初级阶段」');
  });
}
