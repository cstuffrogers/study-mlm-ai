// D171 门禁（单机版）：整体立场判读，不能只靠关键词就拦。
//
// 与 backend/tests/test_d171_holistic_stance.py 同口径：
//   引号内 / 带引述框架 / 同句有转折纠偏词 / （输入侧）用户在提问 → 放行
//   批判对象术语的定义-比较-教学式使用                        → 标注（notes），不拦
//   作者自己的结论句                                          → 拦
//
// 真实体检结论（改之前）：涉及批判对象术语的教学式回答 8 条 → 7 条被拦；
// 单机版拿输出侧规则审**用户提问** 13 条 → 4 条被拒答。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_guard.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'package:marxism_reader/widgets/stance_note_chip.dart';

const _mustPass = [
  // 批判性引用批判对象术语
  '卢卡奇的物化概念是错误的，它把商品拜物教等同于异化。',
  '伯恩斯坦的和平长入社会主义是修正主义谬误，必须批判。',
  '葛兰西的文化领导权理论偏离了无产阶级专政，是错误路线。',
  '阿尔都塞的多元决定论歪曲了经济基础决定上层建筑的原理。',
  // 术语的中性/教学式使用
  '物化劳动指凝结在产品中的劳动，活劳动指正在进行的劳动。',
  '从总体性上把握这一节，就是说不要把某一句孤立起来读。',
  // 引述 + 反驳
  '有人说经济基础与上层建筑相互决定，这种说法错在哪里？',
  '「阶级斗争已经过时」是资产阶级的论调，必须驳斥。',
  '历史决定论（把历史看成宿命）不是马克思的观点。',
  '文化决定论是唯心史观，不能用来解释社会形态更替。',
  // 正统表述（不能被新规则误伤）
  '按毛泽东的说法，两类矛盾性质不同，解决的方法也不同。',
  '群众路线是一切为了群众，一切依靠群众，从群众中来，到群众中去。',
  '剩余价值不存在于流通领域，它产生于生产过程。',
  '资本主义不是历史的终点，两个必然仍然是我们的结论。',
  '文化不能决定社会的发展方向，是社会存在决定社会意识。',
];

const _mustBlock = [
  '经济基础与上层建筑相互决定。',
  '意识决定物质，精神创造客观世界。',
  '阶级斗争已经过时了。',
  '文化决定社会的发展方向。',
  '技术决定社会形态的更替。',
  '地理环境决定社会制度的性质。',
  '剩余价值并不存在，利润来自企业家的才能。',
  '阶级斗争只是话术，现实里早已消失。',
  '资本主义是历史的终点，不会灭亡。',
  '卢卡奇的物化理论揭示了资本主义异化的本质。',
  '阿尔都塞的多元决定概念丰富了马克思主义。',
  '葛兰西的文化领导权理论超越了无产阶级专政的局限。',
  '哈贝马斯的生活世界理论为马克思主义提供了新基础。',
  '运动就是一切，最终目的是微不足道的。',
  '话语建构塑造了社会现实，超越经济决定论。',
  '总体性是把握社会整体的根本方法。',
  '文化领导权比暴力革命更重要，应放弃专政。',
  '马克思主义只是众多宏大叙事中的一种。',
];

const _userQuestions = [
  '为什么说「阶级斗争已经过时」这种说法是错的？',
  '阶级斗争已经过时的论调错在哪里？',
  '卢卡奇的物化理论讲了什么？我要写作业。',
  '从总体性上把握这一段，应该怎么读？',
  '物化劳动和活劳动的区别是什么？',
  '意识决定物质这句话错在哪里？',
  '文化领导权和文化自信是一回事吗？',
];

void main() {
  setUpAll(() async {
    await OfflineContent.ensureMeta();
  });

  test('正例（含指出反面例子）必须全部放行', () {
    for (final t in _mustPass) {
      final r = OfflineGuard.check(t);
      expect(r.blocked, isFalse, reason: '正确的批判性表述被拦：$t（命中 ${r.hits}）');
    }
  });

  test('负例（自述偏离断言）拦截率 ≥90%', () {
    final blocked = _mustBlock.where((t) => OfflineGuard.check(t).blocked).toList();
    final rate = blocked.length / _mustBlock.length;
    expect(rate, greaterThanOrEqualTo(0.9),
        reason: '漏拦：${_mustBlock.where((t) => !blocked.contains(t)).toList()}');
  });

  test('输入侧：提问里引用错误说法不算用户立场', () {
    for (final q in _userQuestions) {
      final r = OfflineGuard.check(q, contextMode: 'input');
      expect(r.blocked, isFalse, reason: '用户提问被拒答：$q（命中 ${r.hits}）');
    }
  });

  test('输入侧放宽只针对提问/引述，直陈表态仍拦', () {
    expect(
        OfflineGuard.check('经济基础与上层建筑相互决定。', contextMode: 'input')
            .blocked,
        isTrue);
  });

  test('术语中性使用 → 标注（notes）而不是整段拦截', () {
    final r = OfflineGuard.check('物化劳动指凝结在产品中的劳动。');
    expect(r.blocked, isFalse);
    expect(r.notes, isNotEmpty, reason: '标注必须回传，UI 要提示「立场待核」');
    expect(r.notes.first['term'], '物化');
  });

  test('一个术语不再能整段拦掉回答', () {
    expect(
        OfflineGuard.check('我来解释这一节：卢卡奇的物化讲的是商品关系变成物与物的关系。')
            .blocked,
        isFalse);
  });

  test('跨句不串味：前句批判、后句裸断言仍拦', () {
    expect(
        OfflineGuard.check('阶级斗争已经过时的错误论调，应当批判。但是意识决定物质。')
            .blocked,
        isTrue);
  });

  test('新补的漏拦断言已随导出进单机数据', () async {
    await OfflineContent.ensureMeta();
    final keys = ((OfflineContent.guard['stance_patterns'] as Map?) ?? const {})
        .keys
        .map((e) => '$e')
        .toSet();
    for (final k in [
      'deny_surplus_value',
      'capitalism_eternal',
      'class_struggle_dismissed',
      'culture_techno_determinism',
      'deny_party_leadership',
    ]) {
      expect(keys.contains(k), isTrue, reason: '离线资产缺规则：$k');
    }
  });

  testWidgets('标注条：默认一行摘要，点开才展开理由', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StanceNoteChip(notes: [
          {'term': '物化', 'school': '卢卡奇', 'reason': '涉及批判对象「物化」，未见明确批判姿态；标注待核，不拦截'},
        ]),
      ),
    ));
    expect(find.textContaining('立场待核 1 处'), findsOneWidget);
    expect(find.textContaining('标注待核'), findsNothing, reason: '默认不展开');
    await tester.tap(find.textContaining('立场待核'));
    await tester.pumpAndSettle();
    expect(find.textContaining('标注待核'), findsOneWidget);
  });
}
