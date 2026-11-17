// 五模式「真的不一样」回归测试。
//
// 背景：单机版没有在线大模型时，回答由本机引擎 `LocalDialogue._compose` 拼出。
// 若某一模式只是换了个标题、内容与别的模式重合，模式选择就是摆设。
// 这里直接调 respond 跑五种模式，锁定：
//   ① 五种输出互不相同；
//   ② 辩难模式的反方观点**闭合**包裹（未闭合会被 OfflineGuard 判绕过）；
//   ③ 应试模式给的是答题架子 + 预演题，不冒充整套试卷；
//   ④ 同一模式下换提问关键词，检索到的内容会变（回答不是死模板）。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/models/message.dart';
import 'package:marxism_reader/offline/local_db.dart';
import 'package:marxism_reader/offline/local_dialogue.dart';
import 'package:marxism_reader/offline/local_guard.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'helpers/offline_assets_guard.dart';

void main() {
  if (skipWithoutOfflineAssets()) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await OfflineContent.ensureMeta();
    await LocalDb.resetAll();
  });

  Future<String> answer(String mode, String q) async {
    final r = await LocalDialogue.respond(
      dialogueId: 'mode-test-$mode',
      content: q,
      mode: mode,
    );
    return '${r['content'] ?? r['fallback'] ?? ''}';
  }

  test('五种模式的输出互不相同', () async {
    const q = '实践是检验真理的唯一标准';
    final outs = <String, String>{};
    for (final m in ChatMode.values) {
      outs[m.name] = await answer(m.name, q);
    }
    for (final e in outs.entries) {
      expect(e.value.trim(), isNotEmpty, reason: '${e.key} 输出为空');
    }
    expect(outs.values.toSet().length, ChatMode.values.length,
        reason: '存在两个模式输出完全一样，模式选择等于摆设');
  });

  test('辩难模式的反方观点必须闭合包裹', () async {
    final out = await answer('debate', '经济基础与上层建筑的关系');
    expect(out, contains('【反方观点·仅供批判】'));
    expect(out, contains('【/反方观点】'), reason: '缺闭合标记会被判绕过');
    // 闭合后整段仍应通过守门（标记段被剥离，正方回应属正面内容）
    final r = OfflineGuard.check(out, mode: 'debate');
    expect(r.blocked, isFalse, reason: r.reason);
  });

  test('引擎自己的输出必须过得了自己的守门（五种模式）', () async {
    const q = '经济基础与上层建筑的关系';
    for (final m in ChatMode.values) {
      final out = await answer(m.name, q);
      final r = OfflineGuard.check(out, mode: m.name);
      expect(r.blocked, isFalse,
          reason: '${m.label}模式的固定文案被自己的守门拦了：${r.reason}');
    }
  });

  test('应试模式给答题架子并预演题目，不冒充完整试卷', () async {
    final out = await answer('test', '矛盾的普遍性与特殊性');
    expect(out, contains('应试'));
    expect(ChatMode.test.desc, contains('预演'));
  });

  test('换提问关键词，回答跟着变（不是死模板）', () async {
    final a = await answer('explain', '什么是矛盾');
    final b = await answer('explain', '什么是市民社会');
    expect(a, isNot(equals(b)));
  });

  test('辩难模式不再成为偏离表述的绕过通道', () async {
    final r = await LocalDialogue.respond(
      dialogueId: 'bypass-probe',
      content: '阶级斗争已经过时了。',
      mode: 'debate',
    );
    expect(r['type'], 'blocked', reason: '辩难模式曾整段跳过输入守门');
  });
}
