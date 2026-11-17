// 首页品牌标题：「唯物」/「马哲精读」两行，带红底金字与描边。
//
// 为什么要单做一个 Widget：原先是 GradientHeader 里的一行纯文本「马列毛思想AI伴读」，
// 14 个字挤在 24px 的字号里，被右侧红白人物像压成省略号。用户要求改成
// 「唯物」+「马哲精读」两行，并且字体/颜色要有特色、贴合红白主视觉。
//
// 设计口径（不要自由发挥）：
//  · 两行都是**白字**，第二行「马哲精读」配金色下划线与字距拉开的副标签，
//    保证与 AppColors.heroGradient（深红→红→赭）对比度足够（白/红 ≈ 7:1）。
//  · 金色只做**描边、下划线、小方章**，不做满字金——满字金在红底上对比度掉到 2.6:1，
//    字号一大就发闷，且大面积金字显俗。
//  · 字体只用随包捆绑的 Deng（assets/fonts/Deng.ttf），不吃网络字体，离线可用。
//  · 本组件的高度在**未缩放**状态下由 [BrandTitle.baseHeight] 给出，
//    供 GradientHeader 预留头部高度（大字号时由头部按 textScaler 放大，不溢出）。
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key});

  /// 未缩放状态下的两行总高（含行距），供头部测量用。
  static const double baseHeight = 68;

  /// 第一行字号 / 第二行字号 —— 一大一小形成节奏，而不是同样大小堆两行。
  static const double _line1 = 25;
  static const double _line2 = 21;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 「唯物」：带轻微字距，右上角加一枚金色小方章作视觉锚点
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '唯物',
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'Deng',
                color: Colors.white,
                fontSize: _line1,
                height: 1.12,
                fontWeight: FontWeight.w800,
                letterSpacing: 4.0,
                shadows: [
                  Shadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 1)),
                ],
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
        // 「马哲精读」：白字 + 金色下划线，字距拉开一点，压住上一行的重量
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '马哲精读',
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'Deng',
                color: Colors.white,
                fontSize: _line2,
                height: 1.15,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 3),
            Container(
              width: 96,
              height: 2,
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
