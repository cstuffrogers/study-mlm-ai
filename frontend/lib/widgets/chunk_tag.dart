// 原文分片可点击按钮 —— 点击弹出对应原文卡片
//
// 设计目标：界面里统一只显示「相关原文」四个字，不再把 `CH-ME-TH-06-1`
// 之类分片编码暴露给用户；点一下拉取 /api/chunks/{id}，用底部弹层展示：
//   著作 · 位置 / 层级 / 权威度 / 正文 / 溯源三校验。
//   内部数据仍按分片 id 索引，界面层与 id 解耦（提升可读性 + 少渲染长文本）。
//
// 复用点：章节测试解析、知识点详情、章节导读、测试历史（错题本）等处。
import 'package:flutter/material.dart';
import '../services/content_service_api.dart';
import '../theme/app_theme.dart';
import 'chat_markdown.dart';
import 'speak_button.dart';

/// 分片详情缓存：同一条分片反复点开不再重复请求 / 解码。
final Map<String, Map<String, dynamic>> _chunkCache = <String, Map<String, dynamic>>{};

/// 清除分片缓存（内容库更新 / 测试时可用）。
void clearChunkCache() {
  _chunkCache.clear();
  _chunkInFlight.clear();
}

final Map<String, Future<Map<String, dynamic>>> _chunkInFlight =
    <String, Future<Map<String, dynamic>>>{};

/// 合并同一分片的并发请求，成功结果与失败结果都进入短缓存。
/// 取单个分片的详情（带进程内缓存）。界面若需自行定位原文，用这个而不是直连 API。
Future<Map<String, dynamic>> chunkDetail(String id) => _chunkDetail(id);

Future<Map<String, dynamic>> _chunkDetail(String id) {
  final hit = _chunkCache[id];
  if (hit != null) return Future.value(hit);
  final running = _chunkInFlight[id];
  if (running != null) return running;
  final f = () async {
    try {
      final j = await ContentApi().chunk(id);
      if ((j['error'] ?? '') == 'not_found') {
        return <String, dynamic>{'_error': '未找到该分片'};
      }
      _chunkCache[id] = j;
      return j;
    } catch (e) {
      return <String, dynamic>{'_error': '$e'};
    } finally {
      _chunkInFlight.remove(id);
    }
  }();
  _chunkInFlight[id] = f;
  return f;
}

/// 分片 id 前缀 → 中文可读来源（仅用于无网/占位场景的友好文案）。
String chunkIdLabel(String id) {
  if (id.startsWith('CH-MLTH-')) return '《关于费尔巴哈的提纲》';
  // 旧占位 id（历史数据 / 离线缓存里可能仍有），正文已于 D107 入库到 CH-MLTH-
  if (id.startsWith('CH-ME-TH-')) return '《关于费尔巴哈的提纲》';
  if (id.startsWith('CH-DZ-')) return '《大众哲学》（艾思奇）';
  if (id.startsWith('CH-ZXBJ-')) return '《哲学笔记》（列宁）';
  if (id.startsWith('GUIDE-')) return '学习导读（非原著正文）';
  return '原著原文';
}

const Map<int, String> _layerLabel = {
  1: 'L1 原文',
  2: 'L2 命题',
  3: 'L3 注释',
  4: 'L4 解析',
};

/// 打开某分片对应的原文卡片（底部弹层）。供各处入口统一调用。
Future<void> showChunkCard(BuildContext context, String chunkId, {String? fallbackText}) async {
  if (chunkId.trim().isEmpty) return;
  // `GUIDE-<章节>`：溯源锚在「本章导读」，本来就没有原著分片可取。
  // 这里不能去请求 /api/chunks，否则只能弹「载入失败」。
  if (chunkId.startsWith('GUIDE-')) {
    _showGuideSourceSheet(context, fallbackText);
    return;
  }
  final c = await _chunkDetail(chunkId);
  final err = c['_error'] as String?;
  if (!context.mounted) return;

  // 载入失败时不要把前缀猜出来的著作名当成已确认来源展示
  final source = err != null ? '相关原文' : (c['source'] ?? chunkIdLabel(chunkId)).toString();
  final location = err != null ? '' : (c['source_location'] ?? '').toString();
  final layer = (c['layer'] as num?)?.toInt() ?? 0;
  final authority = (c['authority_score'] as num?)?.toDouble();
  final orthodoxy = (c['orthodoxy_tag'] ?? '').toString();
  final text = (c['text'] ?? fallbackText ?? '').toString();

  showModalBottomSheet(
    context: context,
    showDragHandle: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.94,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 拖动手柄
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                decoration: BoxDecoration(
                    color: AppColors.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            // 标题行：来源 · 位置 + 小喇叭（不显示分片编码）
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 14, 8),
              child: Row(children: [
                const Icon(Icons.menu_book_outlined, size: 18, color: AppColors.brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stripChunkCodes(location.isEmpty ? source : '$source · $location'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.ink700,
                      fontFamily: 'Deng',
                      fontFamilyFallback: ['Deng', 'Roboto', 'WarnSym'],
                    ),
                  ),
                ),
                SpeakButton(
                  id: 'chunk-$chunkId',
                  text: ChatMarkdown.toSpeech(text),
                  resolveText: () async {
                    final full = (await _chunkDetail(chunkId))['text']?.toString() ?? '';
                    return full.trim().isEmpty ? null : ChatMarkdown.toSpeech(full);
                  },
                ),
              ]),
            ),
            // 徽章行：只保留读者关心的层级 / 权威度 / 正统标签
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (layer > 0) _badge(_layerLabel[layer] ?? 'L$layer', AppColors.brand),
                  if (authority != null)
                    _badge('权威度 ${(authority * 100).round()}%', const Color(0xFF0F766E)),
                  if (orthodoxy.isNotEmpty) _badge(orthodoxy, const Color(0xFF92400E)),
                ],
              ),
            ),
            const Divider(height: 1),
            // 正文（可滚动，完整不截断）
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (err != null && text.isEmpty)
                      Text('载入失败：$err',
                          style: const TextStyle(color: AppColors.danger, fontSize: 13))
                    else if (text.isEmpty)
                      const Text('（此处暂无正文）',
                          style: TextStyle(color: AppColors.ink400, fontSize: 13))
                    else
                      ChatMarkdown(text: text, baseColor: AppColors.ink700),
                    const SizedBox(height: 14),
                    // 溯源说明：仅在确实拉到入库分片时才声明「真实入库」，
                    // 且不把内部编码显示给用户。
                    if (err == null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.brand.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '溯源：本卡片对应原著正文，题目/回答须指向该处方可通过正统性校验。',
                          style: TextStyle(fontSize: 11.5, color: AppColors.ink500, height: 1.5),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 导读溯源卡片：题目/知识点溯源写成 `GUIDE-<章节>` 时，如实说明「这是本章导读，
/// 不是原著正文」，不伪造原文片段。
void _showGuideSourceSheet(BuildContext context, String? fallbackText) {
  final text = (fallbackText ?? '').trim();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(
                    color: AppColors.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Row(children: [
                const Icon(Icons.article_outlined, size: 18, color: AppColors.brand),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('溯源：本章导读（非原著正文）',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '本题的溯源指向本章「学习导读」（老师写的内容梳理），不是原著原文分片。'
                      '想读原文请用本章的「阅读本章原文」入口，那里逐段都可点开核对。',
                      style: TextStyle(fontSize: 13, height: 1.6, color: AppColors.ink700),
                    ),
                    if (text.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Text('本题解析',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(text,
                          style: const TextStyle(
                              fontSize: 12.5, height: 1.6, color: AppColors.ink700)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _badge(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w700)),
    );

/// 可点击「相关原文」按钮。非空 id 才可点；界面不暴露分片编码。
class ChunkTag extends StatelessWidget {
  final String chunkId;
  /// 兼容旧调用方保留参数，但不再显示前缀文字。
  final String? prefixText;
  final String? fallbackText;
  final String? tooltip;
  final bool compact;
  /// 按钮文案，默认「相关原文」。
  final String label;

  const ChunkTag({
    super.key,
    required this.chunkId,
    this.prefixText,
    this.fallbackText,
    this.tooltip,
    this.compact = false,
    this.label = '相关原文',
  });

  @override
  Widget build(BuildContext context) {
    if (chunkId.trim().isEmpty) return const SizedBox.shrink();
    // 导读溯源不要写成「原文分片」，否则读者点开发现没有正文会以为坏了。
    final effectiveLabel = chunkId.startsWith('GUIDE-')
        ? '溯源 本章导读'
        : label;
    final tag = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => showChunkCard(context, chunkId, fallbackText: fallbackText),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 2 : 4),
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.brand.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.link, size: 13, color: AppColors.brand),
              const SizedBox(width: 4),
              Text(
                // 按钮上一律只显示文字，绝不带 `CH-xxx` 分片编码。
                stripChunkCodes(effectiveLabel).isEmpty
                    ? '相关原文'
                    : stripChunkCodes(effectiveLabel),
                style: TextStyle(
                  fontSize: compact ? 11 : 11.5,
                  color: AppColors.brand,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Deng',
                  fontFamilyFallback: const ['Deng', 'Roboto', 'WarnSym'],
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.open_in_new, size: 11, color: AppColors.brand),
            ],
          ),
        ),
      ),
    );
    return tooltip == null
        ? tag
        : Tooltip(message: tooltip!, child: tag);
  }
}
