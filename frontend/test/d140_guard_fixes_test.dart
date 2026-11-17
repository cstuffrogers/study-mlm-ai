// D140 门禁：APP 端「老是被拦截」的三处根因修复。
//
// 用户实报：AI 对话频繁弹出「这段表述涉及与本课程立场不一致的框架…已按防偏离规则
// 拦截」。核查到三个互不相干的根因，这里各钉一条：
//
// ① **把选中的原著当成用户表态**。`respond()` 旧实现拿 `question = content + 选区`
//    送 `OfflineGuard.check`。用户选中恩格斯「经济不是唯一决定性的因素」这类原话，
//    整条对话就被判偏离、直接拒答。史料不是用户立场 —— 输入侧只审用户自己写的话。
// ② **未闭合标记吃掉整段回答**（已完成的重试之外再兜一层）：重试仍漏闭合时，
//    旧实现让整段回答不展示；现在删掉标记字面复检，通过就展示、且不给豁免。
// ③ **提示词只有 7 条**：禁止清单（西马/后马/后现代）、术语红线 6 条、拒答协议
//    在单机版全缺。这里钉住它们必须出现在提示里。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_dialogue.dart';
import 'package:marxism_reader/offline/local_guard.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'helpers/offline_assets_guard.dart';

void main() {
  if (skipWithoutOfflineAssets()) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await OfflineContent.ensureMeta();
  });

  group('① 选中原文不再被当成用户表态', () {
    // 同一句话：用户自己说 → 必须拦；只作为选中原文 → 不能拦。
    // 旧实现把 `question = content + 选区` 一起送审，两条路径必有一错——实测是
    // 「只选中」也被拦（用户实报的「老是被拦截」）。
    const deviant = '经济基础与上层建筑相互决定。';

    test('同一句只作选区时不拦（旧实现会整条拒答）', () async {
      final r = await LocalDialogue.respond(
        dialogueId: 'd140-a',
        content: '这句话怎么理解？',
        selectedText: deviant,
      );
      expect(r['type'], isNot('blocked'), reason: '选区是史料，不是用户表态');
      expect(r['content'], isNotNull);
    });

    test('同一句由用户自己写 → 仍拦（证明上一条不是因为规则失效）', () async {
      final r = await LocalDialogue.respond(
        dialogueId: 'd140-a2',
        content: deviant,
      );
      expect(r['type'], 'blocked');
    });

    test('用户自己写偏离断言仍必须拦（输入侧没被整体放开）', () async {
      final r = await LocalDialogue.respond(
        dialogueId: 'd140-b',
        content: '经济基础和上层建筑相互决定。',
      );
      expect(r['type'], 'blocked');
      expect(r['allow_critical_reading'], isTrue);
    });

    test('选区里带被禁框架、提问本身正常 → 不拦', () async {
      final r = await LocalDialogue.respond(
        dialogueId: 'd140-c',
        content: '这段话在说什么？',
        selectedText: '卢卡奇认为无产阶级是历史的主客体统一。',
      );
      expect(r['type'], isNot('blocked'));
    });
  });

  group('② 未闭合标记不再吃掉整段回答', () {
    test('删标记字面后正文一字不减，且与正文原文一致', () {
      const raw = '【反方观点·仅供批判】对方会说实践只是个人行为。【/反方观点】'
          '所以实践是社会的实践。';
      final cleaned = OfflineGuard.stripMarkerLiterals(raw);
      expect(cleaned.contains('【'), isFalse, reason: '标记字面必须全部删掉');
      expect(cleaned.contains('对方会说实践只是个人行为。'), isTrue);
      expect(cleaned.contains('所以实践是社会的实践。'), isTrue);
    });

    test('未闭合的开标记也能删（不是只删成对的）', () {
      final cleaned =
          OfflineGuard.stripMarkerLiterals('【反方观点·仅供批判】对方会说实践只是个人行为。');
      expect(cleaned, '对方会说实践只是个人行为。');
    });

    test('删标记**不给豁免**：内容真偏离照样拦', () {
      final cleaned = OfflineGuard.stripMarkerLiterals(
          '【辩难】经济基础与上层建筑相互决定。【/辩难】');
      expect(OfflineGuard.check(cleaned).blocked, isTrue,
          reason: '救援只解决格式，不能变成绕过立场校验的通道');
    });
  });

  group('③ 单机提示词补齐禁止清单 / 术语红线 / 拒答协议', () {
    late String p;

    setUp(() {
      p = LocalDialogue.systemPromptFor('explain', false);
    });

    test('知识边界禁止清单（西马/后马/后现代）', () {
      expect(p.contains('西方马克思主义'), isTrue);
      expect(p.contains('后马克思主义'), isTrue);
      expect(p.contains('后现代主义'), isTrue);
      expect(p.contains('不作「另一种视角」引入'), isTrue,
          reason: '只写「禁止」模型会绕成「中立的另一种视角」');
    });

    test('术语红线六条（物质/实践/矛盾/市民社会/物化/反映/决定）', () {
      for (final s in ['物质≠', '实践≠', '矛盾≠', '市民社会≠', '物化≠', '反映≠', '决定≠']) {
        expect(p.contains(s), isTrue, reason: '缺术语红线：$s');
      }
      expect(p.contains('反映是能动的'), isTrue, reason: '毛的能动反映论必须在红线里说清');
    });

    test('拒答协议：不承认「多种解读」，但不误伤原著内部论战', () {
      expect(p.contains('不得说「马克思主义有多种解读」'), isTrue);
      expect(p.contains('原著内部确有论战'), isTrue,
          reason: '否则「毛为什么批苏联教科书」会被判成禁区（库内就有这部原著）');
      expect(p.contains('对苏联教科书的批评'), isTrue);
    });

    test('新增条款不破坏标记纪律（成对 + 退出口仍在）', () {
      for (final prompt in [
        LocalDialogue.systemPromptFor('debate', false),
        LocalDialogue.systemPromptFor('explain', true),
        p,
      ]) {
        expect(prompt.contains('成对闭合'), isTrue);
        expect(prompt.contains('不需要标记时就不要写标记'), isTrue);
      }
    });
  });

  group('④ 后端/前端同口径：正统限定语豁免', () {
    test('恩格斯「归根到底」句式放行', () {
      final r = OfflineGuard.check(
          '历史过程中的决定性因素归根到底是现实生活的生产和再生产。'
          '经济不是唯一决定性的因素。');
      expect(r.blocked, isFalse, reason: '这是恩格斯的原话（1890 致布洛赫）');
    });

    test('毛《实践论》的能动反映论放行', () {
      final r = OfflineGuard.check(
          '机械反映论是错误的，马克思主义的反映论是能动的革命的反映论。');
      expect(r.blocked, isFalse);
    });

    test('裸的「相互决定」仍拦（豁免没被放大成后门）', () {
      expect(OfflineGuard.check('经济基础与上层建筑相互决定。').blocked, isTrue);
      expect(OfflineGuard.check('多种因素共同决定历史进程。').blocked, isTrue);
      // 用否决词「共同决定」给「归根到底」打掩护 → 仍拦
      expect(
          OfflineGuard.check('经济基础与上层建筑相互决定，归根到底两者共同决定历史。')
              .blocked,
          isTrue);
    });
  });
}
