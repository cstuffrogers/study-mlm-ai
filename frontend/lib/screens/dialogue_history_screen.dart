// 对话历史页 — 会话列表 + 消息回看（用户/AI 气泡、相关原文、防偏离拦截标记）
// 数据来自 GET /api/dialogue/list/{user} 与 /api/dialogue/{id}/messages
//
// 口径：界面不显示 [CH-...] / GUIDE- 等内部原文编码；每条助手消息只给一个
// 「相关原文」按钮，点击列出该消息关联的原文片段（关键词检索，非逐条权威溯源）。
import 'package:flutter/material.dart';
import '../services/content_service_api.dart';
import '../widgets/anim.dart';
import '../widgets/chat_markdown.dart';
import '../widgets/related_original_button.dart';
import '../widgets/speak_button.dart';
import '../theme/app_theme.dart';

class DialogueHistoryScreen extends StatefulWidget {
  const DialogueHistoryScreen({super.key});

  @override
  State<DialogueHistoryScreen> createState() => _DialogueHistoryScreenState();
}

class _DialogueHistoryScreenState extends State<DialogueHistoryScreen> {
  List<Map<String, dynamic>>? _list;
  bool _loading = true;
  String? _error;
  String? _currentDialogueId;
  String _currentTitle = '';
  List<Map<String, dynamic>> _messages = const [];
  bool _loadingMessages = false;

  @override
  void initState() {
    super.initState();
    _loadList();
  }

  Future<void> _loadList() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await DialogueApi().list();
      if (list.isNotEmpty) {
        _currentDialogueId ??= list.first['id'].toString();
      }
      if (!mounted) return;
      setState(() { _list = list; _loading = false; });
      if (_currentDialogueId != null) await _loadMessages(_currentDialogueId!);
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _loadMessages(String id) async {
    setState(() { _loadingMessages = true; });
    try {
      final msgs = await DialogueApi().messages(id);
      if (!mounted) return;
      setState(() { _messages = msgs; _loadingMessages = false; });
      for (final d in (_list ?? [])) {
        if (d['id'].toString() == id) {
          _currentTitle = (d['title'] ?? d['id']).toString();
          break;
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _loadingMessages = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('对话历史'),
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loadList,
          ),
        ],
      ),
      body: Row(
        children: [
          SizedBox(width: 260, child: _buildListPane()),
          const VerticalDivider(width: 1),
          Expanded(child: _buildMessagePane()),
        ],
      ),
    );
  }

  Widget _buildListPane() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _list == null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('加载失败：$_error', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.ink500)),
      ));
    }
    final list = _list ?? [];
    if (list.isEmpty) return const Center(child: Text('暂无对话记录', style: TextStyle(color: AppColors.ink400)));
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final d = list[i];
        final id = d['id'].toString();
        final title = (d['title'] ?? id).toString();
        final selected = id == _currentDialogueId;
        return ListTile(
          selected: selected,
          selectedTileColor: AppColors.brandSoft,
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Text('${d['mode'] ?? 'explain'} · ${d['message_count'] ?? 0} 条消息',
              style: const TextStyle(fontSize: 11, color: AppColors.ink400)),
          onTap: () {
            _currentDialogueId = id;
            _currentTitle = title;
            _loadMessages(id);
          },
        );
      },
    );
  }

  Widget _buildMessagePane() {
    if (_currentDialogueId == null) {
      return const Center(child: Text('选择左侧会话查看', style: TextStyle(color: AppColors.ink400)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(_currentTitle.isEmpty ? _currentDialogueId! : _currentTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink700)),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loadingMessages
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
                  ? const Center(child: Text('该会话暂无消息', style: TextStyle(color: AppColors.ink400)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                      itemCount: _messages.length,
                      itemBuilder: (ctx, index) => AnimatedEntrance(
                        delayMs: (index % 8) * 30,
                        child: _bubble(_messages[index], index),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _bubble(Map<String, dynamic> m, int index) {
    final isUser = (m['role'] ?? '').toString() == 'user';
    final content = (m['content'] ?? '').toString();
    final safe = (m['is_safe'] ?? true) == true;
    final related = _relatedIds(m, content);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 560,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? AppColors.brand : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: isUser ? null : Border.all(color: safe ? AppColors.line : AppColors.danger.withValues(alpha: 0.5)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!safe)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.shield_outlined, size: 14, color: AppColors.danger),
                SizedBox(width: 4),
                Text('防偏离拦截', style: TextStyle(fontSize: 11, color: AppColors.danger, fontWeight: FontWeight.w700)),
              ]),
            ),
          // 小喇叭：朗读这条消息（内部编码在 toSpeech 里已剥离）
          Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              SpeakButton(
                id: 'hist-$index',
                compact: true,
                text: ChatMarkdown.toSpeech(content),
                onDark: isUser,
              ),
            ],
          ),
          const SizedBox(height: 4),
          ChatMarkdown(
            text: content,
            baseColor: isUser ? Colors.white : AppColors.ink700,
          ),
          // 统一「相关原文」入口：不显示分片编码、不显示编号列表。
          if (!isUser && related.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: RelatedOriginalButton(chunkIds: related),
            ),
        ]),
      ),
    );
  }

  /// 正文标记 + 历史记录里的 source_chunks 合并去重，仅作为按钮取数用。
  List<String> _relatedIds(Map<String, dynamic> m, String content) {
    final ids = <String>{};
    final out = <String>[];
    void add(String? id) {
      final v = (id ?? '').trim();
      if (v.isNotEmpty && ids.add(v)) out.add(v);
    }

    for (final id in ChatMarkdown.chunkIdsIn(content)) {
      add(id);
    }
    final chunks = (m['source_chunks'] as List?) ?? const [];
    for (final c in chunks) {
      if (c is Map) {
        add(c['chunk_id']?.toString() ?? c['id']?.toString());
      } else {
        add(c?.toString());
      }
    }
    return out;
  }
}
