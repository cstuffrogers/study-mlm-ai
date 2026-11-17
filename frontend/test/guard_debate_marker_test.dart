// 辩难模式「标记豁免」边界回归测试。
//
// 背景（修复前的真漏洞）：前端 OfflineGuard 没有后端 orthodoxy.py 的两道闸：
//   ① `_strip_exempt_segments`：只有**被标记包裹**的段才免检；
//   ② `_has_unclosed_exempt_marker`：标记未闭合直接判绕过。
// 前端旧实现只给了一个 `allowCritical` 布尔，于是 local_dialogue 把
// `mode == 'debate'` 当成整段免检 → 「选辩难模式 + 配在线模型」可让被禁框架
// 的术语原样展示。这里锁定修复后的口径。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/offline/local_guard.dart';
import 'package:marxism_reader/offline/offline_content.dart';
import 'helpers/offline_assets_guard.dart';

void main() {
  if (skipWithoutOfflineAssets()) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await OfflineContent.ensureMeta();
  });

  const term = '文化领导权'; // critical_objects 术语（葛兰西）

  test('标记未闭合 → 直接判绕过，且优先于其它判定', () {
    // 开标记写了、闭合标记漏了
    final r = OfflineGuard.check('【反方观点·仅供批判】$term 是核心机制。', mode: 'debate');
    expect(r.blocked, isTrue, reason: '未闭合标记必须拦截');
    expect(r.hits, contains('unclosed_marker'));
    expect(r.reason, contains('未闭合'));
  });

  test('标记成对 + 术语在标记内 → 辩难模式放行', () {
    final r = OfflineGuard.check(
      '【反方观点·仅供批判】$term 是核心机制。【/反方观点】\n'
      '批判：这套说法把文化斗争从阶级关系中抽离出来，属于错误框架。',
      mode: 'debate',
    );
    expect(r.blocked, isFalse, reason: r.reason);
    expect(r.terms, isEmpty, reason: '标记内的批判对象术语不再算误用');
  });

  test('标记成对但术语在标记外 → 仍算术语误用（不免检）', () {
    final r = OfflineGuard.check(
      '【反方观点·仅供批判】某观点。【/反方观点】\n$term 值得认真对待。',
      mode: 'debate',
    );
    expect(r.terms, contains(term), reason: '标记外的批判对象术语不得凭空免检');
  });

  test('辩难模式不能成为偏离句式的绕过通道', () {
    final r = OfflineGuard.check('阶级斗争已经过时了。', mode: 'debate');
    expect(r.blocked, isTrue, reason: '标记外的裸断言仍须拦截');
  });

  test('批判对象标记未闭合同样拦截', () {
    final r = OfflineGuard.check('【批判对象·非借鉴】$term 的意义', mode: 'explain');
    expect(r.blocked, isTrue);
    expect(r.reason, contains('批判对象'));
  });

  test('普通文本无标记 → 与旧口径一致（不误伤）', () {
    for (final t in [
      '实践是检验真理的唯一标准。',
      '阶级斗争已经过时的错误论调，应当批判。',
    ]) {
      final r = OfflineGuard.check(t, mode: 'debate');
      expect(r.blocked, isFalse, reason: '$t → ${r.reason}');
    }
  });
}
