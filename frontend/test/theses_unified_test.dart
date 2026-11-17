// D131 门禁：《提纲》11 条与前端口径一致，别再漂回别的译本。
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/data/theses.dart';

void main() {
  test('11 条条文齐全且段落号连续', () {
    expect(kTheses.length, 11);
    for (var i = 0; i < kTheses.length; i++) {
      expect(kTheses[i].paragraphId, 'th${i + 1}');
      expect(kTheses[i].index, i + 1);
      expect(kTheses[i].text.trim(), isNotEmpty);
    }
  });

  test('第六条不含第七条内容（串条回归）', () {
    final th6 = kTheses.firstWhere((t) => t.paragraphId == 'th6').text;
    final th7 = kTheses.firstWhere((t) => t.paragraphId == 'th7').text;
    expect(th6.contains('费尔巴哈没有看到'), isFalse);
    expect(th7.contains('费尔巴哈没有看到'), isTrue);
  });

  test('用库内通行本措辞，不用别的译本', () {
    final joined = kTheses.map((t) => t.text).join();
    expect(joined.contains('在其现实性上'), isFalse);
    expect(joined.contains('社会的人类'), isFalse);
    expect(joined.contains('社会化了的人类'), isTrue);
    expect(joined.contains('人的本质并不是单个人所固有的抽象物'), isTrue);
  });

  test('引号成对（「」『』“” 都不许落单）', () {
    for (final t in kTheses) {
      for (final pair in [
        ['「', '」'],
        ['『', '』'],
        ['“', '”'],
      ]) {
        final open = RegExp(RegExp.escape(pair[0])).allMatches(t.text).length;
        final close = RegExp(RegExp.escape(pair[1])).allMatches(t.text).length;
        expect(open, close, reason: '${t.paragraphId} 的 ${pair[0]}${pair[1]} 不配对');
      }
    }
  });
}
