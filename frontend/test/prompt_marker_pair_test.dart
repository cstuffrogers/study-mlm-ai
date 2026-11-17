// 系统提示里的「标记成对闭合」门禁。
//
// 背景（用户实报）：对话里出现
//   「（在线模型这段表述涉及与本课程立场不一致的框架（unclosed_marker）…）」
// 根因不是内容偏离，而是**提示词只给了开标记**：
// 单机版 `_systemPrompt` 在辩难/批判性阅读下只写「标记【反方观点·仅供批判】」，
// 从不给闭合标记 `【/反方观点】`。模型照提示写 → 开闭计数不等 →
// `OfflineGuard._unclosedMarkerName` 判成绕过 → 整段回答不展示，回落本机引擎。
// 后端 `prompt_engineering.yaml` 给的是成对标记 + 「必须成对闭合」，所以没这个问题。
//
// 这里钉住三件事：成对标记都在提示里、明确要求闭合、且不诱导不需要标记的模式。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_dialogue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('辩难模式：开标记与闭合标记都必须出现在提示里', () {
    final p = LocalDialogue.systemPromptFor('debate', false);
    expect(p.contains('【反方观点·仅供批判】'), isTrue,
        reason: '辩难模式要摆反方最强论证，必须给开标记');
    expect(p.contains('【/反方观点】'), isTrue,
        reason: '只给开标记，模型必然漏写闭合 → 整段回答被 unclosed_marker 拦掉');
  });

  test('批判性阅读：同样给成对标记', () {
    final p = LocalDialogue.systemPromptFor('explain', true);
    expect(p.contains('【反方观点·仅供批判】'), isTrue);
    expect(p.contains('【/反方观点】'), isTrue);
  });

  test('批判对象标记也是成对的（两个开闭都要给）', () {
    final p = LocalDialogue.systemPromptFor('explain', true);
    expect(p.contains('【批判对象·非借鉴】'), isTrue);
    expect(p.contains('【/批判对象】'), isTrue);
  });

  test('明确告知「必须成对闭合」以及不成对的后果', () {
    for (final prompt in [
      LocalDialogue.systemPromptFor('debate', false),
      LocalDialogue.systemPromptFor('explain', true),
      LocalDialogue.systemPromptFor('explain', false),
    ]) {
      expect(prompt.contains('成对闭合'), isTrue,
          reason: '要写明规则，不能只给字面标记');
      expect(prompt.contains('不会被展示') || prompt.contains('拦截'), isTrue,
          reason: '让模型知道代价，比只给语法更有效');
    }
  });

  test('释义模式不出现「当前是」的标记指令（避免模型无谓加标记）', () {
    final p = LocalDialogue.systemPromptFor('explain', false);
    expect(p.contains('当前是「辩难」'), isFalse);
    expect(p.contains('当前是「批判性阅读」'), isFalse);
  });

  test('提示末尾有「不需要标记时就不要写」的退出口', () {
    final p = LocalDialogue.systemPromptFor('debate', false);
    expect(p.contains('不需要标记时就不要写标记'), isTrue,
        reason: '否则模型会给整段回答套标记，反而把正文也变成免检段');
  });
}
