// 立场守门「自指批判语境」回归测试。
//
// 背景：修复前用纯正则对整段文本 hasMatch，导致用户**正确批判错误观点**时也被拦：
//   「阶级斗争已经过时的错误论调，应当批判。」→ 被 BLOCK（错的）
// 修法：与后端 core/guard/orthodoxy.py 同一套判定——命中若落在含批判语境词的
// **同一句**内，判为「批判性引用」放行；裸断言仍拦截。
// 这里锁定两类边界：正确的批判必须放行，裸断言与跨句串味必须仍拦截。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_guard.dart';
import 'package:marxism_reader/offline/offline_content.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await OfflineContent.ensureMeta();
  });

  // (输入, 是否应被拦截)
  const cases = <(String, bool)>[
    // —— 必须在同一句里表达「这是错误论调」，应放行 ——
    ('阶级斗争已经过时的错误论调，应当批判。', false),
    ('有人主张经济基础不是唯一决定因素，这种观点是错误的。', false),
    ('意识决定物质的说法属于唯心主义谬误，必须批判。', false),
    // —— 裸断言，必须拦截 ——
    ('阶级斗争已经过时了。', true),
    ('经济基础不是唯一决定因素。', true),
    ('意识决定物质，这是不是也行？', true),
    // —— 跨句不得串味：前句批判、后句裸断言，仍必须拦截 ——
    ('阶级斗争已经过时的错误论调，应当批判。但是意识决定物质。', true),
    ('阶级斗争已经过时了。阶级斗争已经过时的错误论调应当批判。', true),
    // —— 标记字面内含「批判」二字，不得当成语境证据 ——
    ('【反方观点·仅供批判】阶级斗争已经过时了。【/反方观点】', true),
  ];

  test('自指批判语境放行、裸断言仍拦截', () {
    for (final (text, shouldBlock) in cases) {
      final r = OfflineGuard.check(text);
      expect(r.blocked, shouldBlock, reason: '判定不符：$text → ${r.status}/${r.reason}');
    }
  });

  test('批判对象标记必须真的包住术语才算立场已表明', () {
    const term = '文化领导权'; // critical_objects 里的代表性术语（葛兰西）
    // 标记在后、术语在前 → 未包裹 → 仍算术语误用
    expect(OfflineGuard.check('$term 的单向度的人值得一读。\n【批判对象·非借鉴】说明【/批判对象】')
        .terms, isNotEmpty);
    // 真的包起来 → 立场已表明
    expect(OfflineGuard.check('【批判对象·非借鉴】$term 的单向度的人【/批判对象】').terms, isEmpty);
  });

  test('偏离关键词不再包含马列核心术语「资产阶级」', () {
    // 「资产阶级」是正统核心术语，放进偏离词会导致正确选项/正确表述被误判
    expect(OfflineGuard.deviationKeywords, isNot(contains('资产阶级')));
    expect(OfflineGuard.deviationKeywords, isNot(contains('博弈论')));
  });

  test('含「资产阶级」的正确表述不被拦截', () {
    for (final t in [
      '推翻资产阶级统治、消灭阶级与私有制，实现共产主义',
      '它以劳动为同一尺度，仍带有资产阶级法权痕迹，是形式上的平等',
      '扬弃了资产阶级孤立个人的抽象预设，指向自由联合、社会化的人类',
    ]) {
      expect(OfflineGuard.check(t).blocked, isFalse, reason: t);
    }
  });
}
