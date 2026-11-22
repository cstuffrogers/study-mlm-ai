// 全站通用的「选中文本追问」浮标 + 「自由浮动对话按钮」。
//
// 设计要点（与 work_reader_screen / chapter_guide_screen 共用，避免重复实现）：
//   · SelectionAskPanel —— 选中正文后浮出的追问条：复制 / 标色(可选) / 朗读 + 五模式
//     （释义/追问/辩难/关联/应试）各一枚 chip，点任一模式即把选中文本送进会话浮窗。
//   · MovableChatFab —— 常驻的自由浮动对话按钮（不绑定某个卡片），按住可任意拖动，
//     点击打开/收起 AI 会话浮窗。
// 拖动统一用 `_DragHandle`：只包住标题/拖拽把手，正文与按钮保持原生点击手势。
import 'package:flutter/material.dart';

import '../models/message.dart';
import '../theme/app_theme.dart';
import 'speak_button.dart';

/// 选中文本后的浮动追问面板内容（不含定位，由外层 MovableBox 负责位置/拖动）。
class SelectionAskPanel extends StatelessWidget {
  final String text;
  final String speakId;
  final VoidCallback onCopy;
  final VoidCallback? onAnnotate;
  final VoidCallback? onDismiss;
  final void Function(ChatMode mode) onAsk;
  const SelectionAskPanel({
    super.key,
    required this.text,
    required this.speakId,
    required this.onCopy,
    required this.onAsk,
    this.onAnnotate,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.soft),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          _mini(Icons.copy_rounded, '复制', AppColors.ink700, onCopy),
          const Spacer(),
          if (onAnnotate != null) _mini(Icons.color_lens_rounded, '标色', AppColors.gold, onAnnotate!),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: SpeakButton(id: speakId, compact: true, text: text),
          ),
          const Spacer(),
          if (onDismiss != null)
            _mini(Icons.close_rounded, '关闭', AppColors.ink400, onDismiss!),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 4, runSpacing: 4, children: ChatMode.values.map((m) {
          return ActionChip(
            visualDensity: VisualDensity.compact,
            label: Text(m.label, style: const TextStyle(fontSize: 11.5, color: Colors.white)),
            backgroundColor: Color(m.color),
            onPressed: () => onAsk(m),
          );
        }).toList()),
      ]),
    );
  }

  static Widget _mini(IconData ic, String label, Color c, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(ic, size: 18, color: c),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 9.5, color: AppColors.ink500)),
        ]),
      ),
    );
  }
}

/// 自由浮动的对话按钮：按住「把手」可任意拖到屏幕任意位置，点击则开/关 AI 会话浮窗。
class MovableChatFab extends StatefulWidget {
  final Offset initialOffset;
  final Size bounds;
  final VoidCallback onTap;
  final bool open;
  const MovableChatFab({
    super.key,
    required this.initialOffset,
    required this.bounds,
    required this.onTap,
    this.open = false,
  });

  @override
  State<MovableChatFab> createState() => _MovableChatFabState();
}

class _MovableChatFabState extends State<MovableChatFab> {
  static const double _w = 60;
  static const double _h = 60;
  late Offset _pos = _clamp(widget.initialOffset);

  Offset _clamp(Offset p) {
    final maxX = (widget.bounds.width - _w - 8).clamp(8.0, double.infinity);
    final maxY = (widget.bounds.height - _h - 8).clamp(8.0, double.infinity);
    return Offset(p.dx.clamp(8.0, maxX), p.dy.clamp(8.0, maxY));
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _pos.dx,
      top: _pos.dy,
      child: GestureDetector(
        // 只有「按住拖动」时才移动；轻点由下面的 InkWell 触发 onTap。
        onPanUpdate: (d) => setState(() => _pos = _clamp(_pos + d.delta)),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: _w,
              height: _h,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: widget.open ? AppColors.heroGradient : null,
                color: widget.open ? null : Colors.white,
                border: widget.open ? null : Border.all(color: AppColors.line),
                boxShadow: AppShadows.soft,
              ),
              child: Tooltip(
                message: 'AI 对话',
                child: Icon(
                  widget.open ? Icons.close_rounded : Icons.forum_rounded,
                  color: widget.open ? Colors.white : AppColors.brand,
                  size: 26,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
