// 统一设计系统 — 配色 / 渐变 / 表面 / 阴影 / 圆角 / 间距
// 目标：鲜明庄重的「革命红 + 鎏金」气质，配柔和呼吸光晕与过渡。
// 说明：品牌主色改为革命红（党旗红 C8161D），深绛用于头图；金色作点缀高光；
//      绿/琥珀保留为学情语义色（掌握达标 / 复习到期），不与品牌混用。
import 'package:flutter/material.dart';

class AppColors {
  // 主色：革命红（党旗红）
  static const brand = Color(0xFFC8161D);
  static const brandDeep = Color(0xFF7A0E13);
  static const brandSoft = Color(0xFFFCE6E7);
  // 次强调：鎏金（点缀/高光/等级）
  static const gold = Color(0xFFD4A017);
  static const goldSoft = Color(0xFFFBF1DA);
  // 学情语义色
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFD97706);
  static const danger = Color(0xFF991B1B);
  static const info = Color(0xFFB91C1C);
  // 深红强调（进度点缀，保留旧名 ink 以兼容既有引用）
  static const ink = Color(0xFF7A0E13);
  // 中性
  static const ink900 = Color(0xFF1C1412);
  static const ink700 = Color(0xFF3D2F2C);
  static const ink500 = Color(0xFF6B5D59);
  static const ink400 = Color(0xFF9C8F8B);
  static const line = Color(0xFFEADCD7);
  static const surface = Color(0xFFFBF7F5);

  // 品牌线性渐变（主）
  static const brandGradient = LinearGradient(
    colors: [Color(0xFFC8161D), Color(0xFF9E1520)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  // 头图渐变（党旗红→深绛→暗金微光）
  static const heroGradient = LinearGradient(
    colors: [Color(0xFF7A0E13), Color(0xFFC8161D), Color(0xFF9A2B12)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  // 柔和背景渐变（暖白→淡粉）
  static const pageGradient = LinearGradient(
    colors: [Color(0xFFFBF7F5), Color(0xFFF7EDEA)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

class AppRadius {
  static const card = 16.0;
  static const chip = 10.0;
  static const hero = 22.0;
}

class AppShadows {
  static List<BoxShadow> soft = [
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.06),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];
  static List<BoxShadow> lift = [
    BoxShadow(
      color: const Color(0xFFC8161D).withValues(alpha: 0.20),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];
}

class AppTheme {
  static ThemeData build() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      primary: AppColors.brand,
      surface: Colors.white,
    );

    // 全局字体：使用随应用打包的 Deng（等线，GB2312 全集）。
    // 不设置则 Flutter Web 会去 fonts.gstatic.com 拉 Roboto/Noto，
    // 国内被墙会导致中文乱码。同时作为 fontFamilyFallback 兜底图标字形。
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Deng',
      fontFamilyFallback: const ['Deng', 'Roboto', 'WarnSym'],
      // 轻量页面切换：用 FadeUpwards 替代默认的 Zoom（后者在 CanvasKit 下对
      // 整页做缩放+淡入合成，开销更大、切换感更重）。统一 220ms，切换更利落。
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
    final textTheme = base.textTheme.apply(
      bodyColor: AppColors.ink900,
      displayColor: AppColors.ink900,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.surface,
      textTheme: textTheme.copyWith(
        titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.5),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink900,
        titleTextStyle: TextStyle(
          color: AppColors.ink900,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          // AppBar 用 titleTextStyle 直接作为标题的 DefaultTextStyle（不与
          // 主题 body 的 Deng 合并），若不显式指定字族，中文标题会回退到
          // Roboto（无 CJK 字形）→ CanvasKit 渲染成「方框 + X」豆腐块。
          fontFamily: 'Deng',
          fontFamilyFallback: ['Deng', 'Roboto', 'WarnSym'],
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.chip)),
        side: BorderSide.none,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          // ButtonStyle.textStyle 会“替换”标签文本样式（不与 labelLarge/Deng 合并），
          // 若不显式带字族，中文标签会回退 Roboto → 豆腐块。
          textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontFamily: 'Deng',
              fontFamilyFallback: ['Deng', 'Roboto', 'WarnSym']),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: const BorderSide(color: AppColors.line),
          foregroundColor: AppColors.ink700,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.brand),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.brand),
      dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
