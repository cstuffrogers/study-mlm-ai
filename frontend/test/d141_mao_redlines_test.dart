// D141 门禁：毛泽东思想三项基本点（两类矛盾 / 群众路线 / 独立自主）。
//
// 与后端 `tests/test_d141_mao_redlines.py` **同一组用例**、同一份数据：
// 规则写在 `backend/core/guard/orthodoxy.py` 的 STANCE_PATTERNS，
// 由 `scripts/export_offline_assets.py` 导出到 `assets/offline/knowledge.json`，
// 单机版 `OfflineGuard` 直接读它。这里锁「单机版没漏」这件事，
// 一旦有人只改 py 不重跑导出，这条测试就红。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_dialogue.dart';
import 'package:marxism_reader/offline/local_guard.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'helpers/offline_assets_guard.dart';

const _denials = <String>[
  '两类矛盾的区分是虚构的。',
  '不存在两类矛盾，都是阶级斗争。',
  '人民内部矛盾就是敌我矛盾。',
  '群众路线已经过时了。',
  '不必依靠群众，靠制度就行。',
  '群众都是愚昧落后的。',
  '精英必须管理群众。',
  '独立自主已经过时，全球化时代不必自力更生。',
  '中国革命胜利主要归功于苏联援助。',
  '照搬苏联模式才能成功。',
];

const _orthodox = <String>[
  '必须严格区分和正确处理两类不同性质的矛盾。',
  '人民内部矛盾只能用民主的、说服教育的方法解决。',
  '必须坚持群众路线，一切为了群众，一切依靠群众，从群众中来，到群众中去。',
  '必须坚持独立自主、自力更生，同时学习外国先进经验。',
  '照搬苏联模式的教训必须记取。',
  '毛泽东批评了照搬苏联模式的做法。',
  '敌我之间和人民内部这两类矛盾的性质不同，解决的方法也不同。',
];

void main() {
  if (skipWithoutOfflineAssets()) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await OfflineContent.ensureMeta();
  });

  test('三条红线规则已随导出进单机数据（≥12 条 stance_patterns）', () async {
    await OfflineContent.ensureMeta();
    final patterns =
        (OfflineContent.guard['stance_patterns'] as Map?) ?? const {};
    final keys = patterns.keys.map((e) => '$e').toSet();
    expect(keys.contains('deny_two_kinds_contradiction'), isTrue);
    expect(keys.contains('deny_mass_line'), isTrue);
    expect(keys.contains('deny_independence'), isTrue);
    expect(keys.length, greaterThanOrEqualTo(12));
  });

  test('否认两类矛盾 / 群众路线 / 独立自主 → 单机版同样拦', () {
    for (final text in _denials) {
      expect(OfflineGuard.check(text).blocked, isTrue, reason: '应拦未拦：$text');
    }
  });

  test('正统论述（含「照搬苏联模式的教训」）→ 不误拦', () {
    for (final text in _orthodox) {
      final r = OfflineGuard.check(text);
      expect(r.blocked, isFalse,
          reason: '误拦：$text（命中 ${r.hits.join('、')}）');
    }
  });

  group('提示词口径（与后端 prompt_engineering.yaml 对齐）', () {
    late String prompt;
    setUp(() => prompt = LocalDialogue.systemPromptFor('explain', false));

    test('第 10 条改成三层口径：原理层一元 + 具体结论可争 + 原著内部论战', () {
      expect(prompt.contains('原理层是一元的'), isTrue);
      expect(prompt.contains('具体结论可争'), isTrue);
      expect(prompt.contains('原著内部确有论战'), isTrue);
      expect(prompt.contains('多种解读'), isTrue, reason: '禁止表述必须保留');
      // 旧的「正统体系是唯一科学的体系」表述不得再出现（会与毛《整顿党的作风》冲突）
      expect(prompt.contains('唯一科学的体系'), isFalse);
    });

    test('第 11 条三项基本点齐全', () {
      expect(prompt.contains('两类矛盾'), isTrue);
      expect(prompt.contains('群众路线'), isTrue);
      expect(prompt.contains('独立自主'), isTrue);
      expect(prompt.contains('不得否认'), isTrue);
    });
  });

  test('自己在批判这个论调时放行（与后端批判语境同口径）', () {
    // 注意：`allowCritical` 只开「批判对象术语」的口子，不豁免立场模式；
    // 立场模式靠「同一句内有批判语境词」判定，两侧一致。
    final r = OfflineGuard.check('有人说群众路线已经过时了，这种论调是错误的。');
    expect(r.blocked, isFalse);
  });
}
