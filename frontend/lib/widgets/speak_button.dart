// 统一「小喇叭」朗读按钮 —— 点击把文字用浏览器 TTS 读出来，再点停止。
//
// - 全局同一时刻只朗读一个条目：通过 services/tts.dart 的 ttsCurrent 跟踪。
// - 只在 Web 端显示（非 Web 平台 ttsAvailable()==false → 自动隐藏）。
// - 使用 ValueListenableBuilder 局部刷新：只有该按钮自己切换 图标/颜色，
//   不做常驻动画（遵守性能红线，无 .repeat() / Timer）。
import 'package:flutter/material.dart';
import '../services/tts.dart';
import '../theme/app_theme.dart';

class SpeakButton extends StatelessWidget {
  /// 要朗读的纯文本（调用方负责去掉 Markdown 标记）。
  final String text;

  /// 点击时才异步取到完整文本（如从后端拉完整分片正文）；返回非空则优先用它。
  final Future<String?> Function()? resolveText;

  /// 全局唯一标识（用于判断是否正在播放这条）。
  final String id;

  /// 图标颜色；默认品牌红。
  final Color? color;

  /// 紧凑尺寸（用于卡片角落的小图标）。
  final bool compact;

  /// 背景是否反转（用于深色/红色气泡上反白）。
  final bool onDark;

  const SpeakButton({
    super.key,
    required this.text,
    required this.id,
    this.resolveText,
    this.color,
    this.compact = false,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!ttsAvailable() || text.trim().isEmpty) return const SizedBox.shrink();
    final size = compact ? 15.0 : 17.0;
    final box = compact ? 24.0 : 30.0;
    final base = color ?? (onDark ? Colors.white : AppColors.brand);

    return ValueListenableBuilder<String?>(
      valueListenable: ttsCurrent,
      builder: (context, current, _) {
        final playing = current == id;
        final fg = playing ? (onDark ? AppColors.gold : AppColors.gold) : base;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(box / 2),
            onTap: () async {
              if (playing) {
                ttsStop();
              } else {
                var body = text;
                if (resolveText != null) {
                  try {
                    final full = await resolveText!();
                    if (full != null && full.trim().isNotEmpty) body = full;
                  } catch (_) {}
                }
                ttsSpeak(body, id: id);
              }
            },
            child: Tooltip(
              message: playing ? '停止朗读' : '朗读',
              child: Container(
                width: box,
                height: box,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: playing
                      ? (onDark ? Colors.white.withValues(alpha: 0.22) : AppColors.gold.withValues(alpha: 0.14))
                      : (onDark ? Colors.white.withValues(alpha: 0.14) : base.withValues(alpha: 0.08)),
                  border: Border.all(
                    color: playing
                        ? (onDark ? Colors.white.withValues(alpha: 0.9) : AppColors.gold)
                        : base.withValues(alpha: onDark ? 0.5 : 0.35),
                    width: 1,
                  ),
                ),
                child: Icon(
                  playing ? Icons.stop_rounded : Icons.volume_up_rounded,
                  size: size,
                  color: fg,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
