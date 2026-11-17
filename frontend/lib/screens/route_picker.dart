// 路线选择页（T014）— 渐变头图 + 三卡（入场动画）+ 共享地基说明。
//
// 首页（screens/home_screen.dart）现在就是这一屏；本页保留给
// 「功能中心 → 学习路线」入口，多一个返回箭头。卡片实现见 widgets/route_cards.dart，
// 两处共用一份，避免文案/徽标漂移。
import 'package:flutter/material.dart';
import '../widgets/anim.dart';
import '../widgets/route_cards.dart';

class RoutePickerScreen extends StatelessWidget {
  const RoutePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          GradientHeader(
            leading: Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.maybePop(ctx),
              ),
            ),
            title: '选择学习路线',
            subtitle: '三条路线共享公共地基，掌握度跨路线复用',
          ),
          const Expanded(
            child: AuroraBackground(child: RouteCardsView()),
          ),
        ],
      ),
    );
  }
}
