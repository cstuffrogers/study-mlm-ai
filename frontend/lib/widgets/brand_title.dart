// 首页品牌标题：「唯物」/「马哲精读」两行，行楷书法字，金色明亮、四周无黑影。
//
// 为什么要单做一个 Widget：原先是 GradientHeader 里的一行纯文本「马列毛思想AI伴读」，
// 14 个字挤在 24px 的字号里，被右侧红白人物像压成省略号。用户要求改成
// 「唯物」+「马哲精读」两行，并且字体/颜色要有特色、贴合红白主视觉。
//
// 设计口径（用户 2026-11 明确要求）：
//  · **行楷字体**：用随包捆绑的 MaShanZheng（Google Fonts 开源行书，OFL 许可），
//    笔画圆润有力、带书法笔意，是真正的行楷字形，而不是靠字重/描边"模拟"毛笔。
//  · **金色要亮**：不用暗金 #D4A017，改用亮金渐变（#FFE082 → #FFC93C → #FFD54F），
//    在深红 heroGradient 上足够明亮醒目。
//  · **四周不能有黑影**：移除上一版的多层深色描边阴影（那正是被用户否定的"黑影"），
//    改用**渐变文字**（ShaderMask）着色——无边、无投影、无描边。
//  · 字号一大一小形成节奏，字距适度拉开体现"豪迈"。
//  · 行楷字体本身只有 Regular 一个字重，**不要**再叠合成加粗：
//    合成加粗会把书法笔画糊成团、失去笔意。
//  · 右上角保留金色小方章作视觉锚点；第二行保留金色下划线收束。
//  · 本组件的高度在**未缩放**状态下由 [BrandTitle.baseHeight] 给出，
//    供 GradientHeader 预留头部高度（大字号时由头部按 textScaler 放大，不溢出）。
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key});

  /// 未缩放状态下的两行总高（含行距），供头部测量用。
  static const double baseHeight = 78;

  /// 第一行字号 / 第二行字号 —— 一大一小形成节奏，而不是同样大小堆两行。
  static const double _line1 = 34;
  static const double _line2 = 28;

  /// 品牌标题专用行楷字体族名（pubspec.yaml 中注册，assets/fonts/MaShanZheng-Regular.ttf）。
  static const String fontFamily = 'MaShanZheng';

  /// 亮金渐变的三个色标：高光金 → 主金 → 暖金，整体比 AppColors.gold 更亮更发光。
  static const List<Color> _brightGold = [
    Color(0xFFFFE082),
    Color(0xFFFFC93C),
    Color(0xFFFFD54F),
  ];

  /// 用竖直亮金渐变给文字上色。
  ///
  /// 为什么用 ShaderMask 而不是 Text 的 color + shadows：用户明确要求"四周不能有黑影"，
  /// 任何 shadow 都会在笔画外扩出暗色轮廓；渐变着色只改填充色，字形边缘干净。
  Widget _goldText(String text, double fontSize, double letterSpacing) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (Rect bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: _brightGold,
      ).createShader(bounds),
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          fontFamily: fontFamily,
          // 颜色被 ShaderMask 覆盖，这里给白色保证 srcIn 遮罩按字形裁剪。
          color: Colors.white,
          fontSize: fontSize,
          height: 1.15,
          letterSpacing: letterSpacing,
          // 行楷只有一个字重，保持默认，避免合成加粗糊掉笔意。
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 「唯物」：行楷大字，字距拉开，右上角加一枚金色小方章作视觉锚点
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _goldText('唯物', _line1, 6.0),
            const SizedBox(width: 6),
            // 小方章：金色描边 + 内嵌一点，模仿印刷体书名章的样式
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.gold, width: 1.6),
                  borderRadius: BorderRadius.circular(2),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 3,
                  height: 3,
                  decoration: const BoxDecoration(
                    color: AppColors.gold,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        // 「马哲精读」：行楷 + 金色下划线，字距拉开一点，压住上一行的重量
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _goldText('马哲精读', _line2, 4.0),
            const SizedBox(height: 4),
            Container(
              width: 104,
              height: 2.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  AppColors.gold,
                  AppColors.gold.withValues(alpha: 0.15),
                ]),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
