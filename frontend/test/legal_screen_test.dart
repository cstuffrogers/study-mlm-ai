// 「法律与隐私」页回归测试。
//
// 这一页是应用商店审核的硬性项（缺可打开的隐私政策一律退回），
// 所以用测试钉住三件事：
//  1. 四个必备板块都在（免责 / 隐私 / 协议 / 内容版权）；
//  2. 运营者信息未配置时**不编造、也不在用户页面写「未配置」待办**：
//     那几行直接不显示，异议渠道改为项目仓库 Issue；
//  3. 著作权时间窗口的口径要写对（毛/周 75 部、2026-12-31 届满），
//     这是本库唯一还在保护期内的部分，写错就是虚假陈述。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marxism_reader/config/app_meta.dart';
import 'package:marxism_reader/screens/legal_screen.dart';
import 'package:marxism_reader/theme/app_theme.dart';

/// 文案里含 `**加粗**` 标记的段落用 RichText 渲染，
/// `find.textContaining` 只认 Text，所以这里两种都查。
Finder textLike(String needle) => find.byWidgetPredicate(
      (w) =>
          // Text 内部会再建一个 RichText，同一段文案可能命中两次，
          // 所以断言用 findsWidgets（至少渲染出来了），不苛求唯一。
          (w is Text && (w.data ?? '').contains(needle)) ||
          (w is RichText && w.text.toPlainText().contains(needle)),
      description: '文本含「$needle」',
    );

void main() {
  testWidgets('法律与隐私页：六个板块 + AI 生成提示', (t) async {
    await t.binding.setSurfaceSize(const Size(1000, 3000));
    await t.pumpWidget(MaterialApp(theme: AppTheme.build(), home: const LegalScreen()));
    await t.pumpAndSettle();

    expect(find.text('一、免责声明'), findsOneWidget);
    expect(find.text('二、隐私政策'), findsOneWidget);
    expect(find.text('三、用户协议'), findsOneWidget);
    expect(find.text('四、内容来源与版权说明'), findsOneWidget);
    expect(find.text('五、AI 生成内容提示'), findsOneWidget);
    expect(find.text('六、版本与异议处理'), findsOneWidget);

    // 关键事实陈述不能丢：不收集个人信息、无账号、不上传
    expect(textLike('不收集任何个人信息'), findsWidgets);
    expect(textLike('没有账号体系'), findsWidgets);

    // 未配置运营者时：既不编造，也不在用户可见处写「未配置」或开发方待办
    expect(find.text('未配置'), findsNothing);
    expect(textLike('运营者信息未配置'), findsNothing);
    expect(textLike('operatorName'), findsNothing);
    expect(textLike('lib/config/app_meta.dart'), findsNothing);
    // 异议渠道必须仍然可执行：指向项目仓库提交 Issue
    expect(textLike('提交 Issue'), findsWidgets);
    expect(find.text('本页版本'), findsOneWidget);

    await t.binding.setSurfaceSize(null);
  });

  testWidgets('著作权口径：毛/周 75 部仍处保护期，2026-12-31 届满', (t) async {
    await t.binding.setSurfaceSize(const Size(1000, 3000));
    await t.pumpWidget(MaterialApp(theme: AppTheme.build(), home: const LegalScreen()));
    await t.pumpAndSettle();

    expect(AppMeta.copyrightPendingCount, 75);
    expect(AppMeta.contentWorkCount, 229);
    expect(textLike('2026 年 12 月 31 日'), findsWidgets);
    expect(textLike('75 部作品'), findsWidgets);
    // 不得把法律结论说成确定意见
    expect(textLike('不构成法律意见'), findsWidgets);

    await t.binding.setSurfaceSize(null);
  });
}
