// 五模式「真的不一样」回归测试。
//
// 背景：单机版没有在线大模型时，回答由本机引擎 `LocalDialogue._compose` 拼出。
// 若某一模式只是换了个标题、内容与别的模式重合，模式选择就是摆设。
// 这里直接调 respond 跑五种模式，锁定：
//   ① 五种输出互不相同；
//   ② 辩难模式的反方观点**闭合**包裹（未闭合会被 OfflineGuard 判绕过）；
//   ③ 只有「追问」模式把问题抛回去，其余模式（含普通对话）不在结尾追加追问；
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

  test('只有「追问」模式把问题抛回去，其余模式不追加追问', () async {
    const q = '经济基础与上层建筑的关系';
    final dig = await answer('dig', q);
    expect(dig, contains('继续追问'), reason: '追问模式的核心产物就是问题');
    for (final m in [ChatMode.chat, ChatMode.debate, ChatMode.connect]) {
      final out = await answer(m.name, q);
      for (final marker in ['继续追问', '可练的一句', '预演一题']) {
        expect(out, isNot(contains(marker)),
            reason: '${m.label} 模式不该在结尾追加「$marker」');
      }
    }
  });

  test('普通对话不套模式标题架子，直接答', () async {
    final out = await answer('chat', '什么是实践');
    expect(out.trim(), isNotEmpty);
    expect(out, isNot(contains('一句话答')));
    expect(out, isNot(contains('读法建议')));
  });

  test('选区浮框里的「普通对话」把选中原句一起带进来', () async {
    // 选区面板点「普通对话」时：content 是「这段在说什么？」，selectedText 是被选中的那句。
    // 本机引擎必须看得出这是「围绕这句」在答，而不是不看你选了什么。
    const sel = '实践是检验真理的唯一标准';
    final r = await LocalDialogue.respond(
      dialogueId: 'chat-with-selection',
      content: '这段在说什么？',
      selectedText: sel,
      mode: 'chat',
    );
    expect(r['type'], 'ai_message');
    final out = '${r['content'] ?? ''}';
    expect(out, contains('你选的这句'), reason: '带选区时先把这句逐字放回去');
    expect(out, contains(sel), reason: '选中的文字必须进回答的依据');
    // 普通对话仍然是普通对话：不套模式架子、不追加追问
    expect(out, isNot(contains('一句话答')));
    expect(out, isNot(contains('继续追问')));
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
