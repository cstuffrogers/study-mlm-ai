// 相关原文统一入口 —— 点击直接跳到原文（原书阅读器对应位置）。
//
// 用户只需看到「相关原文」一个按钮；分片编码只在数据层用于取正文与定位，
// 不进入任何可见文案。
//   · 只有一个分片 → 直接打开该书阅读器并翻到该分片所在页；
//   · 多个分片 → 先列一条条「著作 · 位置 + 摘录」，点任一条同样跳到正文位置；
//   · 非原著正文分片（导读/解析等）→ 仍用原卡片展示，避免跳错地方。
// 列表页走完整路由（而不是底部弹层），保证不会被浮在 Overlay 里的 AI 会话窗盖住。
import 'package:flutter/material.dart';

import '../screens/work_reader_screen.dart';
import '../theme/app_theme.dart';
import 'chat_markdown.dart';
import 'chunk_tag.dart';

/// 去重保序，丢掉空 id。
List<String> _normalize(List<String> chunkIds) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in chunkIds) {
    final id = raw.trim();
    if (id.isEmpty || !seen.add(id)) continue;
    out.add(id);
  }
  return out;
}

/// 按钮文案固定为「相关原文」。任何调用方都不该把分片编码拼进按钮，
/// 这里再兜一层：带 id 的文案一律退回纯文字，杜绝 `相关原文 CH-YZB-063` 这种残留。
String _cleanLabel(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return '相关原文';
  final cleaned = stripChunkCodes(t);
  if (cleaned.isEmpty || cleaned != t) return '相关原文';
  return cleaned;
}

/// 从 AI 回答 / 历史消息收集到的原文 id 列表（去重保序）打开统一入口。
Future<void> showRelatedOriginals(BuildContext context, List<String> chunkIds,
        {String title = '相关原文'}) =>
    showRelatedOriginalsFrom(Navigator.of(context, rootNavigator: true), chunkIds,
        title: title);

/// 同上，但由调用方指定 Navigator。
/// 浮动会话窗用它：先把自己的 Overlay 关掉再打开原文页，避免会话窗压住原文。
Future<void> showRelatedOriginalsFrom(NavigatorState nav, List<String> chunkIds,
    {String title = '相关原文'}) async {
  final valid = _normalize(chunkIds);
  if (valid.isEmpty) return;
  if (valid.length == 1) {
    await openOriginalAt(nav.context, valid.first);
    return;
  }
  await nav.push(MaterialPageRoute<void>(
    builder: (_) => RelatedOriginalsScreen(ids: valid, title: title),
  ));
}

/// 打开某条原文：能定位就进阅读器对应位置，定位不了才退回分片卡片。
Future<void> openOriginalAt(BuildContext context, String chunkId) async {
  final id = chunkId.trim();
  if (id.isEmpty) return;
  Map<String, dynamic> detail;
  try {
    detail = await chunkDetail(id);
  } catch (_) {
    detail = const {};
  }
  if (!context.mounted) return;
  final layer = (detail['layer'] as num?)?.toInt() ?? 0;
  final source = (detail['source'] ?? '').toString().trim();
  // 只有「原著正文分片」（L1）才跳阅读器；导读/解析类分片留在卡片里展示。
  if (source.isEmpty || layer != 1) {
    await showChunkCard(context, id);
    return;
  }
  await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
    builder: (_) => WorkReaderScreen(work: source, title: source, focusChunkId: id),
  ));
}

/// 「相关原文」列表页：一条条列出真实入库分片，点任一条跳到正文位置。
class RelatedOriginalsScreen extends StatefulWidget {
  final List<String> ids;
  final String title;
  const RelatedOriginalsScreen(
      {super.key, required this.ids, this.title = '相关原文'});

  @override
  State<RelatedOriginalsScreen> createState() => _RelatedOriginalsScreenState();
}

class _RelatedOriginalsScreenState extends State<RelatedOriginalsScreen> {
  final Map<String, Map<String, dynamic>> _details = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final id in widget.ids) {
      try {
        _details[id] = await chunkDetail(id);
      } catch (_) {
        _details[id] = const {};
      }
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF7F5),
      appBar: AppBar(
        title: Text(stripChunkCodes(widget.title),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        backgroundColor: const Color(0xFFFBF7F5),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
              itemCount: widget.ids.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (c, i) => _RelatedTile(
                index: i + 1,
                chunkId: widget.ids[i],
                detail: _details[widget.ids[i]],
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          child: Text(
            '相关原文片段（关键词检索，非逐条权威溯源）· 点任一条可跳到正文对应位置',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppColors.ink400, height: 1.4),
          ),
        ),
      ),
    );
  }
}

class _RelatedTile extends StatelessWidget {
  final int index;
  final String chunkId;
  final Map<String, dynamic>? detail;
  const _RelatedTile({required this.index, required this.chunkId, this.detail});

  @override
  Widget build(BuildContext context) {
    final d = detail ?? const <String, dynamic>{};
    final hasDetail = d.isNotEmpty;
    final source = (d['source'] ?? '').toString();
    final where = (d['source_location'] ?? '').toString();
    final text = (d['text'] ?? '').toString().replaceAll('\n', ' ').trim();
    final layer = (d['layer'] as num?)?.toInt() ?? 0;
    final isOriginal = source.isNotEmpty && layer == 1;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => openOriginalAt(context, chunkId),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text('$index',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandDeep)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  !hasDetail
                      ? '相关原文'
                      : stripChunkCodes([if (source.isNotEmpty) source, if (where.isNotEmpty) where]
                          .join(' · ')),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
              Text(isOriginal ? '跳到原文' : '查看片段',
                  style: const TextStyle(fontSize: 11, color: AppColors.brand)),
              const Icon(Icons.chevron_right, size: 17, color: AppColors.ink400),
            ]),
            if (!hasDetail)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('正在读取原文…',
                    style: TextStyle(fontSize: 11.5, color: AppColors.ink400)),
              ),
            if (text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  text.length > 110 ? '${text.substring(0, 110)}…' : text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink700, height: 1.55),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// 统一的小按钮：所有 AI / 历史气泡复用同一个「相关原文」入口。
class RelatedOriginalButton extends StatelessWidget {
  final List<String> chunkIds;
  final bool compact;
  final String? label;

  /// 打开原文前先执行（浮动会话窗用它把自己撤下来，避免压住原文页）。
  final VoidCallback? onBeforeOpen;

  /// 完全接管打开动作（浮动会话窗：先撤浮窗、读原文、回来再恢复浮窗）。
  final Future<void> Function(List<String> ids)? onOpen;

  const RelatedOriginalButton({
    super.key,
    required this.chunkIds,
    this.compact = false,
    this.label,
    this.onBeforeOpen,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (chunkIds.isEmpty) return const SizedBox.shrink();
    return OutlinedButton.icon(
      icon: Icon(Icons.link, size: compact ? 13 : 14),
      label: Text(_cleanLabel(label)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(
            fontSize: 11,
            fontFamily: 'Deng',
            fontFamilyFallback: ['Deng', 'Roboto', 'WarnSym']),
      ),
      onPressed: () async {
        if (onOpen != null) {
          await onOpen!(chunkIds);
          return;
        }
        final nav = Navigator.of(context, rootNavigator: true);
        onBeforeOpen?.call();
        await showRelatedOriginalsFrom(nav, chunkIds);
      },
    );
  }
}
