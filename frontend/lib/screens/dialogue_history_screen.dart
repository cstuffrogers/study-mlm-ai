// 功能中心 →「对话历史」：本机会话列表 + 消息回看。
//
// 数据源：**本机 LocalDb.dialogues**（单机版全部对话都存在 SharedPreferences）。
// 早先这页读的是后端 `/api/dialogue/*`，单机包没有后端 → 列表永远空，
// 于是出现「左右分栏、左边一片空白」的观感。
//
// 布局口径：
// · 窄屏（手机，<760）：单列——先列表，点一条进消息页（带返回），不再做左右分栏；
// · 宽屏（平板/桌面/Web）：左侧列表 272 + 右侧消息；
// · 气泡宽度用 maxWidth 约束，不做固定 560，避免窄屏横向溢出。
//
// 口径：界面不显示 CH- 等内部原文编码；每条助手消息只给一个「相关原文」入口。
import 'package:flutter/material.dart';

import '../models/message.dart';
import '../offline/local_db.dart';
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
  bool _loading = true;
  List<Map<String, dynamic>> _list = const [];
  /// 窄屏下「已进到哪一段会话」；宽屏忽略它，用 _selectedId。
  String? _openId;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await LocalDb.ensure();
    final docs = LocalDb.dialogues.values
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    // 最近更新在前
    docs.sort((a, b) =>
        '${b['updated_at'] ?? ''}'.compareTo('${a['updated_at'] ?? ''}'));
    if (!mounted) return;
    setState(() {
      _list = docs;
      _loading = false;
      if (_selectedId != null && !docs.any((d) => '${d['id']}' == _selectedId)) {
        _selectedId = null;
      }
      if (_openId != null && !docs.any((d) => '${d['id']}' == _openId)) {
        _openId = null;
      }
    });
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这段会话？'),
        content: const Text('仅删除本机记录，不影响学习进度与答题历史。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    LocalDb.dialogues.remove(id);
    await LocalDb.flushKey('dialogues');
    if (!mounted) return;
    setState(() {
      if (_openId == id) _openId = null;
      if (_selectedId == id) _selectedId = null;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 760;
      if (wide) {
        final selected = _selectedId ??
            (_list.isEmpty ? null : '${_list.first['id']}');
        return Scaffold(
          appBar: AppBar(
            title: const Text('对话历史'),
            backgroundColor: AppColors.brand,
            foregroundColor: Colors.white,
            actions: [_refreshBtn()],
          ),
          body: Row(children: [
            SizedBox(width: 272, child: _listPane(selected, wide: true)),
            const VerticalDivider(width: 1),
            Expanded(child: _messagePane(_docOf(selected))),
          ]),
        );
      }

      // 窄屏：列表与消息二选一
      final doc = _docOf(_openId);
      // 进了会话再按系统返回键，应该回列表而不是直接退出整页
      return PopScope(
        canPop: doc == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _openId = null);
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(doc == null ? '对话历史' : _titleOf(doc)),
            backgroundColor: AppColors.brand,
            foregroundColor: Colors.white,
            leading: doc == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: '返回列表',
                    onPressed: () => setState(() => _openId = null),
                  ),
            actions: doc == null ? [_refreshBtn()] : null,
          ),
          body: doc == null ? _listPane(null, wide: false) : _messagePane(doc),
        ),
      );
    });
  }

  Widget _refreshBtn() => IconButton(
        icon: const Icon(Icons.refresh),
        tooltip: '刷新',
        onPressed: _load,
      );

  Map<String, dynamic>? _docOf(String? id) {
    if (id == null) return null;
    for (final d in _list) {
      if ('${d['id']}' == id) return d;
    }
    return null;
  }

  String _titleOf(Map<String, dynamic> d) {
    final t = '${d['title'] ?? ''}'.trim();
    return t.isEmpty ? '未命名会话' : t;
  }

  // ------------------------------------------------------------- 列表
  /// [wide] 必须由外层 LayoutBuilder 传入：这里再读 MediaQuery.size 会与
  /// 实际布局宽度不一致（测试/分屏场景下曾导致点列表项没反应）。
  Widget _listPane(String? selectedId, {required bool wide}) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_list.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.forum_outlined, size: 44, color: AppColors.ink400),
            SizedBox(height: 12),
            Text('还没有对话记录',
                style: TextStyle(fontSize: 14, color: AppColors.ink500)),
            SizedBox(height: 6),
            Text('在正文选中一句话、点浮窗里的模式追问后，会话会记在这里。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.ink400)),
          ]),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _list.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 12, endIndent: 12),
      itemBuilder: (ctx, i) {
        final d = _list[i];
        final id = '${d['id']}';
        final msgs = (d['messages'] as List?) ?? const [];
        final mode = ChatMode.values.firstWhere(
          (m) => m.name == '${d['current_mode'] ?? ''}',
          orElse: () => ChatMode.chat,
        );
        return ListTile(
          selected: id == selectedId || id == _openId,
          selectedTileColor: AppColors.brandSoft,
          contentPadding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          title: Text(_titleOf(d),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink700)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Color(mode.color).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(mode.label,
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700, color: Color(mode.color))),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text('${msgs.length} 条 · ${_ago(d['updated_at'])}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppColors.ink400)),
              ),
            ]),
          ),
          trailing: IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.ink400),
            onPressed: () => _delete(id),
          ),
          onTap: () => setState(() {
            if (wide) {
              _selectedId = id;
            } else {
              _openId = id;
            }
          }),
        );
      },
    );
  }

  /// 「3 分钟前 / 2 小时前 / 昨天 / 3 天前」——只读本机时间戳，不做时区换算。
  String _ago(Object? raw) {
    final t = DateTime.tryParse('${raw ?? ''}');
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inMinutes < 60) return '${d.inMinutes} 分钟前';
    if (d.inHours < 24) return '${d.inHours} 小时前';
    if (d.inDays == 1) return '昨天';
    if (d.inDays < 30) return '${d.inDays} 天前';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  // ------------------------------------------------------------- 消息
  Widget _messagePane(Map<String, dynamic>? doc) {
    if (doc == null) {
      return const Center(
          child: Text('从列表里选一段会话', style: TextStyle(color: AppColors.ink400)));
    }
    final msgs = ((doc['messages'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          child: Text(_titleOf(doc),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink700)),
        ),
        const Divider(height: 1),
        Expanded(
          child: msgs.isEmpty
              ? const Center(child: Text('该会话暂无消息', style: TextStyle(color: AppColors.ink400)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  itemCount: msgs.length,
                  itemBuilder: (ctx, index) => AnimatedEntrance(
                    delayMs: (index % 8) * 30,
                    child: _bubble(msgs[index], index),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _bubble(Map<String, dynamic> m, int index) {
    final role = '${m['role'] ?? ''}';
    final isUser = role == 'user';
    final blocked = role == 'blocked';
    final content = '${m['content'] ?? ''}';
    final related = _relatedIds(m, content);
    final mode = ChatMode.values.firstWhere(
      (x) => x.name == '${m['mode'] ?? ''}',
      orElse: () => ChatMode.chat,
    );
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        // 不做固定 width，窄屏不再横向溢出
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? AppColors.brand : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: isUser
              ? null
              : Border.all(color: blocked ? AppColors.danger.withValues(alpha: 0.5) : AppColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Color(mode.color).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(mode.label,
                      style: TextStyle(
                          fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(mode.color))),
                ),
                if (blocked) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.shield_outlined, size: 13, color: AppColors.danger),
                  const SizedBox(width: 3),
                  const Text('防偏离拦截',
                      style: TextStyle(
                          fontSize: 10.5, color: AppColors.danger, fontWeight: FontWeight.w700)),
                ],
              ]),
            ),
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
