// 首页品牌标题：「唯物」/「马哲精读」两行，金色毛笔字，强有力、豪迈。
//
// 为什么要单做一个 Widget：原先是 GradientHeader 里的一行纯文本「马列毛思想AI伴读」，
// 14 个字挤在 24px 的字号里，被右侧红白人物像压成省略号。用户要求改成
// 「唯物」+「马哲精读」两行，并且字体/颜色要有特色、贴合红白主视觉。
//
// 设计口径（金色毛笔字风格）：
//  · 两行都是**金色**（AppColors.gold），体现豪迈有力的毛笔字风格。
//  · 用多层 shadows 做深色描边（深红棕，与 heroGradient 背景融合），模拟毛笔
//    粗厚笔画的力道，金色字在深红底上更突出、有"写"出来的质感。
//  · 字号一大一小形成节奏，字距拉开，体现"豪迈"；字重 w900 增强力量感。
//  · 字体只用随包捆绑的 Deng（assets/fonts/Deng.ttf），不吃网络字体，离线可用。
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
  static const double _line1 = 32;
  static const double _line2 = 27;

  /// 深色描边阴影色：深红棕，与 heroGradient（深红→红→赭）背景融合，
  /// 在金色字四周形成粗厚笔画，模拟毛笔落纸的力道。
  static const Color _stroke = Color(0xBD1F0E06);

  /// 描边阴影列表：上下左右 + 斜角 + 底部，形成粗厚描边，让金字有"写"出来的质感。
  static const List<Shadow> _brushStroke = [
    Shadow(color: _stroke, blurRadius: 7, offset: Offset(-2, -2)),
    Shadow(color: _stroke, blurRadius: 7, offset: Offset(2, -2)),
    Shadow(color: _stroke, blurRadius: 7, offset: Offset(-2, 2)),
    Shadow(color: _stroke, blurRadius: 7, offset: Offset(2, 2)),
    Shadow(color: _stroke, blurRadius: 5, offset: Offset(0, 3)),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 「唯物」：金色大字，毛笔描边，字距拉开，右上角加一枚金色小方章作视觉锚点
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '唯物',
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'Deng',
                color: AppColors.gold,
                fontSize: _line1,
                height: 1.1,
                fontWeight: FontWeight.w900,
                letterSpacing: 6.0,
                shadows: _brushStroke,
              ),
            ),
            const SizedBox(width: 6),
            // 小方章：金色描边 + 内嵌一点，模仿印刷体书名章的样式
            Padding(
              padding: const EdgeInsets.only(top: 3),
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
        // 「马哲精读」：金色毛笔字 + 金色下划线，字距拉开一点，压住上一行的重量
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '马哲精读',
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'Deng',
                color: AppColors.gold,
                fontSize: _line2,
                height: 1.12,
                fontWeight: FontWeight.w900,
                letterSpacing: 4.0,
                shadows: _brushStroke,
              ),
            ),
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
