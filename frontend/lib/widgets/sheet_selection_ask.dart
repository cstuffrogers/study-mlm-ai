// 弹层（`showModalBottomSheet`）内部的「选中文本 → 追问浮框」。
//
// 为什么单独一个组件：
//  · 弹层不是页面，正文页那套 `MovableBox`（基于 `Positioned`）放不进去；
//  · 正文页的选文浮框是自己插 `OverlayEntry` + 自己管 `FloatingChat` 生命周期，
//    在弹层里再抄一份必然漏关；
//  · 所以这里只做「半个」浮框：自己负责在弹层里叠一层、负责选文与定位，
//    发问动作交回调用方（`onAsk`）。调用方拿到 mode 后先关弹层，
//    再走它本来就有的会话入口 —— 全应用只有一份会话浮窗实现。
//
// 同时负责屏蔽系统自带的「copy / 全选」工具条（`contextMenuBuilder` 返回空），
// 否则系统菜单和本浮框会同时出现、互相遮挡。
//
// 朗读生命周期也归这里管：浮框里的小喇叭一点就念，浮框一消失（收起 / 发问 /
// 选中别处 / 整个弹层被关）就必须停 —— 否则浮框没了声音还在念（用户实报）。
// 四个退出点都接上：onDismiss、onAsk、选文变化、dispose。
import 'package:flutter/material.dart';
// SelectedContent 在 rendering 里（不是 services）
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';

import '../models/message.dart';
import '../services/tts.dart';
import '../theme/app_theme.dart';
import 'speak_button.dart';

/// 包在可选中正文外层：选中即在本层之上浮出追问条，不弹系统菜单。
class SheetSelectionAsk extends StatefulWidget {
  final Widget child;
  /// 选中后回调：把 mode 交给调用方去发问（调用方负责关弹层再开会话）。
  final void Function(String text, ChatMode mode) onAsk;
  /// 用来生成朗读 id，避免不同分片/页面的朗读互相占用。
  final String speakKey;
  const SheetSelectionAsk({
    super.key,
    required this.child,
    required this.onAsk,
    required this.speakKey,
  });

  @override
  State<SheetSelectionAsk> createState() => _SheetSelectionAskState();
}

class _SheetSelectionAskState extends State<SheetSelectionAsk> {
  String _text = '';

  @override
  void dispose() {
    // 整个弹层被销毁（点遮罩 / 下滑 / 父页面被替换）时浮框也一起没了，
    // 这里是最后一道保险。ttsStop() 幂等，多调无副作用。
    ttsStop();
    super.dispose();
  }

  /// 浮框消失即停朗读。
  void _stopSpeech() => ttsStop();

  void _onSel(SelectedContent? sel) {
    final t = (sel?.plainText ?? '').trim();
    // 太长的选区不当引文用（与正文页同一口径）
    if (t.isEmpty || t.length >= 500) {
      if (_text.isEmpty) return;
      // 浮框要消失 → 它上面那个朗读也必须停
      _stopSpeech();
      setState(() => _text = '');
      return;
    }
    if (t == _text) return;
    // 选区换了：旧浮框连同它的朗读一起作废，否则会念着上一段选文
    if (_text.isNotEmpty) _stopSpeech();
    setState(() => _text = t);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: SelectionArea(
            // 屏蔽系统工具栏：这里选中文字的意图是追问，不是复制。
            contextMenuBuilder: (_, _) => const SizedBox.shrink(),
            onSelectionChanged: _onSel,
            child: widget.child,
          ),
        ),
        if (_text.isNotEmpty)
          Positioned(
            left: 10,
            right: 10,
            top: 6,
            child: Material(
              color: Colors.transparent,
              child: _AskBar(
                key: ValueKey('${_text.length}-${_text.hashCode}'),
                text: _text,
                speakId: 'chunk-sel-${widget.speakKey}-${_text.hashCode}',
                onCopy: () {
                  Clipboard.setData(ClipboardData(text: _text));
                  // 复制后浮框自动收起，朗读跟着停
                  _stopSpeech();
                  setState(() => _text = '');
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
                  );
                },
                onAsk: (m) {
                  // 点模式即收起浮框（后续由调用方关弹层/进阅读器），朗读必须停
                  _stopSpeech();
                  widget.onAsk(_text, m);
                },
                onDismiss: () {
                  _stopSpeech();
                  setState(() => _text = '');
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _AskBar extends StatelessWidget {
  final String text;
  final String speakId;
  final VoidCallback onCopy;
  final void Function(ChatMode mode) onAsk;
  final VoidCallback onDismiss;
  const _AskBar({
    super.key,
    required this.text,
    required this.speakId,
    required this.onCopy,
    required this.onAsk,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.soft,
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            _mini(Icons.copy_rounded, '复制', AppColors.ink700, onCopy),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: SpeakButton(id: speakId, compact: true, text: text),
            ),
            const Spacer(),
            _mini(Icons.close_rounded, '关闭', AppColors.ink400, onDismiss),
          ]),
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 4, children: kSelectionModes.map((m) {
            return ActionChip(
              visualDensity: VisualDensity.compact,
              label: Text(m.label, style: const TextStyle(fontSize: 11.5, color: Colors.white)),
              backgroundColor: Color(m.color),
              onPressed: () => onAsk(m),
            );
          }).toList()),
        ],
      ),
    );
  }

  static Widget _mini(IconData ic, String label, Color c, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ic, size: 16, color: c),
          const SizedBox(width: 3),
          Text(label, style: const TextStyle(fontSize: 9.5, color: AppColors.ink500)),
        ]),
      ),
    );
  }
}
