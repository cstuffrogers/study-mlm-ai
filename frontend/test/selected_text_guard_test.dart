// D133 门禁：选中原文片段在**单机版**也要按联网版同口径净化。
//
// 漏洞原状：后端 `DialogueService.chat()` 只查 `u.content`，`selected_text`
// 原样进 prompt；单机版 `LocalDialogue.respond()` 直接把 selectedText 拼进检索串。
// 正文页 `SelectionArea` 允许整章全选，于是「几万字一次」两端都能发生。
// 后端已修（`_safe_selected_text`：正则判注入 + 关键词命中回查原著 + 1200 字截断），
// 这里锁单机版的**同值**截断与清洗。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_dialogue.dart';

void main() {
  test('控制字符清掉、空白保留语义', () {
    expect(LocalDialogue.sanitizeSelection('原\u0000文\u0007片段'), '原文片段');
    expect(LocalDialogue.sanitizeSelection('  实践是认识的基础  '), '实践是认识的基础');
    expect(LocalDialogue.sanitizeSelection(''), '');
  });

  test('超长截断到 1200 字并加说明（与后端 _MAX_SELECTED_TEXT 同值）', () {
    expect(LocalDialogue.maxSelectedText, 1200);
    final out = LocalDialogue.sanitizeSelection('字' * 5000);
    expect(out.length, 1200 + '……（选中过长，已截断）'.length);
    expect(out.startsWith('字' * 1200), isTrue);
    expect(out.endsWith('……（选中过长，已截断）'), isTrue);
  });

  test('正常长度的原文片段一字不改', () {
    const quote = '现在你是说自己的话了，说自己的实话和真心话了。';
    expect(LocalDialogue.sanitizeSelection(quote), quote);
  });
}
