// 会话浮层 — Sheet Modal，展示会话历史 + 输入框 + blocked 状态 + 溯源卡片

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_service.dart';
import '../models/message.dart';
import '../widgets/chat_markdown.dart';
import '../widgets/related_original_button.dart';
import '../widgets/instant_summary_card.dart';
import '../widgets/speak_button.dart';
import '../theme/app_theme.dart';

class ChatSheet extends StatelessWidget {
  const ChatSheet({super.key});

  @override
  Widget build(BuildContext context) {
    // 复用顶层 ChatService（main.dart 注入），不在此创建新实例
    return const _ChatBody();
  }
}

class _ChatBody extends StatelessWidget {
  const _ChatBody();

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<ChatService>();
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            _buildHeader(context, svc),
            Expanded(
              child: svc.turns.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppColors.brandSoft,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.touch_app_outlined, size: 30, color: AppColors.brand),
                        ),
                        const SizedBox(height: 12),
                        const Text('选中原文唤起 AI 开始对话',
                            style: TextStyle(color: AppColors.ink400)),
                      ]),
                    )
                  : ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.all(12),
                      itemCount: svc.turns.length,
                      itemBuilder: (_, i) => _buildTurn(context, svc.turns[i], svc, i),
                    ),
            ),
            _buildInput(context, svc),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ChatService svc) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: const BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Expanded(
            child: Text(svc.status,
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
          ),
          // 模式选择框（5 模式）：鎏金加粗箭头 + 描边底座，保证箭头清晰可见
          Container(
            height: 36,
            padding: const EdgeInsets.only(left: 12, right: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.85), width: 1),
            ),
            child: DropdownButton<ChatMode>(
              value: svc.currentMode,
              underline: const SizedBox(),
              isDense: true,
              dropdownColor: AppColors.brandDeep,
              borderRadius: BorderRadius.circular(10),
              iconSize: 24,
              iconEnabledColor: AppColors.gold,
              // DropdownButton 的 style / item style 会“替换”而非合并外层
              // DefaultTextStyle，若不带字族，中文会回退 Roboto → 豆腐块。
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600,
                  fontFamily: 'Deng', fontFamilyFallback: ['Deng', 'Roboto', 'WarnSym']),
              items: ChatMode.values
                  .map((m) => DropdownMenuItem(
                      value: m,
                      child: Text(m.label,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600,
                              fontFamily: 'Deng', fontFamilyFallback: ['Deng', 'Roboto', 'WarnSym']))))
                  .toList(),
              onChanged: (m) => m != null ? svc.switchMode(m) : null,
            ),
          ),
          const SizedBox(width: 4),
          // 批判性阅读开关：做成有底的圆形按钮，图标始终清晰可见
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: svc.criticalReading ? 0.24 : 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                  color: svc.criticalReading
                      ? const Color(0xFFFCA5A5)
                      : Colors.white.withValues(alpha: 0.5),
                  width: 1),
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 20,
              icon: Icon(Icons.swap_horiz,
                  color: svc.criticalReading ? const Color(0xFFFCA5A5) : Colors.white),
              tooltip: svc.criticalReading ? '批判性阅读: 开' : '批判性阅读: 关',
              onPressed: svc.toggleCriticalReading,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTurn(BuildContext context, ChatTurn t, ChatService svc, int index) {
    // 会话历史彩色竖线（5模式5色，NFR-019）
    final modeColor = ChatMode.values.firstWhere(
      (m) => m.name == t.mode,
      orElse: () => ChatMode.explain,
    ).color;

    if (t.role == 'user') {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10, left: 40),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(
                  color: AppColors.brand.withValues(alpha: 0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(t.content, style: const TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(width: 6),
                  SpeakButton(
                    id: 'user-$index',
                    compact: true,
                    onDark: true,
                    color: Colors.white,
                    text: ChatMarkdown.toSpeech(t.content),
                  ),
                ],
              ),
              if (t.selectedText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('锚点: «${t.selectedText.length > 30 ? '${t.selectedText.substring(0, 30)}…' : t.selectedText}»',
                      style: const TextStyle(color: Color(0xFFFDE7C9), fontSize: 10)),
                ),
            ],
          ),
        ),
      );
    }

    final isBlocked = t.role == 'blocked';
    return Container(
      margin: const EdgeInsets.only(bottom: 10, right: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(14),
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
        border: Border(left: BorderSide(color: Color(modeColor), width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isBlocked)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                border: Border.all(color: const Color(0xFFFECACA)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.block, color: Color(0xFFE11D48), size: 16),
                    SizedBox(width: 4),
                    Text('防偏离拦截', style: TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.bold, fontSize: 13)),
                  ]),
                  const SizedBox(height: 4),
                  Text(t.content, style: const TextStyle(color: Color(0xFF7F1D1D))),
                  if (t.blockedReason != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('原因: ${t.blockedReason}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFFB91C1C))),
                    ),
                ],
              ),
            )
          else ...[
            if (t.engine.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(children: [
                  Icon(
                      t.engine.startsWith('cloud')
                          ? Icons.cloud_done_rounded
                          : Icons.offline_bolt_rounded,
                      size: 12,
                      color: AppColors.ink400),
                  const SizedBox(width: 4),
                  Text(
                      // 「AI 生成」标识：按《人工智能生成合成内容标识办法》要求明示，
                      // 不能只写引擎名，要让读者一眼看出这不是原著原文。
                      '${t.engine.startsWith('cloud:')
                          ? '在线模型 · ${t.engine.substring('cloud:'.length)}'
                          : (t.engine == 'local:guard-fallback'
                              ? '本机引擎（在线回答被立场层拦截）'
                              : '本机引擎')} · AI 生成',
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.ink400)),
                ]),
              ),
            // 朗读按钮行（右上角小喇叭）
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SpeakButton(
                  id: 'turn-$index-${t.mode}',
                  compact: true,
                  text: ChatMarkdown.toSpeech(t.content),
                ),
              ],
            ),
            ChatMarkdown(text: t.content, baseColor: AppColors.ink900),
          ],
          if (t.instantSummary != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InstantSummaryCard(
                oneLine: t.instantSummary!['one_line'] ?? '',
                checkQuestion: t.instantSummary!['check_question'] ?? '',
              ),
            ),
          if (_relatedIds(t).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: RelatedOriginalButton(chunkIds: _relatedIds(t)),
            ),
        ],
      ),
    );
  }

  /// 正文内的内部编码 + RAG 溯源卡片合并为一个「相关原文」入口。
  /// 界面只显示按钮文字，不显示 CH-/GUIDE- 编号或数量。
  List<String> _relatedIds(ChatTurn t) {
    final ids = <String>{};
    final out = <String>[];
    void add(String? id) {
      final v = (id ?? '').trim();
      if (v.isNotEmpty && ids.add(v)) out.add(v);
    }

    for (final id in t.sourceChunks) {
      add(id);
    }
    for (final id in ChatMarkdown.chunkIdsIn(t.content)) {
      add(id);
    }
    for (final c in t.provenance) {
      add(c.chunkId);
    }
    return out;
  }

  Widget _buildInput(BuildContext context, ChatService svc) {
    final controller = TextEditingController();
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: '输入追问...',
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) {
                    svc.send(content: v.trim());
                    controller.clear();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: AppColors.brand.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: () {
                  final v = controller.text.trim();
                  if (v.isNotEmpty) {
                    svc.send(content: v);
                    controller.clear();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
