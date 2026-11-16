// 会话气泡 Markdown + 数学公式渲染
//
// 需求：AI 回复里的 Markdown（标题/列表/加粗/代码/引用/表格）与 LaTeX 数学公式
// （$...$ 行内、$$...$$ 或 \[...\] 块级）要正确排版显示，而不是当纯文本。
//
// 结构：
//   - 普通文本段（含 Markdown + 数学）→ MarkdownBody + flutter_markdown_latex 的
//     LatexElementBuilder / LatexBlockSyntax / LatexInlineSyntax（离线 KaTeX 字体随包）。
//   - 豁免段（【反方观点·仅供批判】/【批判对象·非借鉴】）→ 沿用原 ExemptBlock 的彩色标注框
//     视觉（FR-006/FR-007），但框内正文同样按 Markdown + 数学渲染（不再当纯文本）。
//   - 模型为溯源校验输出的 `[CH-...]` / `[GUIDE-...]` 内部编码：**渲染前全部剥离**，
//     界面不向用户暴露分片编号；由气泡层统一提供一个「相关原文」按钮。
//
// 性能：MarkdownStyleSheet / ExtensionSet / 纯文本派生结果均缓存，长会话滚动不再
// 每条消息重复构造样式与跑正则。
//
// 字体红线（D69/D72 同类）：MarkdownStyleSheet 里的 TextStyle 会“替换”正文默认样式，
// 必须显式带 fontFamily:'Deng' + fallback，否则中文回退 Roboto → 豆腐块。

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:markdown/markdown.dart' as md;

import '../theme/app_theme.dart';

/// AI 回答里的内部溯源标记：`[CH-ME-TH-02-1]`、`[CH-SHJ-102]`、`[GUIDE-...]`。
/// 后端三重校验仍需要模型输出这些标记，前端只把它们当作「取原文 id」的数据，
/// 不渲染成文字/链接；朗读、折叠预览、正文渲染共用同一正则，避免规则漂移。
final RegExp chunkTagRegex = RegExp(r'\[((?:CH|GUIDE)-[A-Za-z0-9-]+)\]');

/// 任何界面文案里的内部溯源编码（`CH-YZB-063` 或带方括号的 `[CH-YZB-063]`）。
/// 「相关原文」按钮上曾会把编码拼在文案后面，所有面向用户的地方都过一遍这个正则。
final RegExp anyChunkCodeRegex =
    RegExp(r'\[?\b(?:CH|GUIDE)-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\]?');

/// 去掉文案里的内部分片编码，并收拾留下的空括号/多余空白。
String stripChunkCodes(String s) {
  if (!s.contains('CH-') && !s.contains('GUIDE-')) return s;
  return s
      .replaceAll(anyChunkCodeRegex, '')
      .replaceAll(RegExp(r'[\[\]【】]\s*[\[\]【】]'), '') // 剩下的空括号对
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .trim();
}

/// 该 href 是否是历史版本生成的分片链接（保留给兼容判断）。
bool isChunkTagHref(String? href) => (href ?? '').startsWith('chunk:');

/// 从 href 里取回分片 id（保留给兼容判断）。
String chunkIdFromHref(String href) => href.substring('chunk:'.length);

/// 小容量派生结果缓存：同一段 AI 文本反复 build 时不再重复跑正则。
final Map<String, String> _stripCache = <String, String>{};
final Map<String, String> _speechCache = <String, String>{};
final Map<String, String> _previewCache = <String, String>{};
final Map<String, List<String>> _idsCache = <String, List<String>>{};

void _guardCache(Map<Object, Object> m) {
  if (m.length > 256) m.clear();
}

class ChatMarkdown extends StatelessWidget {
  final String text;
  final Color baseColor;
  /// 兼容旧调用方：正文已不再渲染分片链接，此回调保留但不再触发。
  /// 需要「相关原文」入口请使用 chunkIdsIn() + showRelatedOriginals()。
  final void Function(String chunkId)? onChunkTap;

  const ChatMarkdown({
    super.key,
    required this.text,
    this.baseColor = AppColors.ink900,
    this.onChunkTap,
  });

  /// 去掉正文里的内部溯源编码（界面不显示 CH- / GUIDE- 编号）。
  static String stripChunkTags(String s) {
    final hit = _stripCache[s];
    if (hit != null) return hit;
    final out = s.replaceAll(chunkTagRegex, '');
    _guardCache(_stripCache);
    _stripCache[s] = out;
    return out;
  }

  /// 提取一段 AI 文本里出现过的分片 id（去重保序），供「相关原文」按钮使用。
  static List<String> chunkIdsIn(String s) {
    final hit = _idsCache[s];
    if (hit != null) return hit;
    final seen = <String>{};
    final ids = <String>[];
    for (final m in chunkTagRegex.allMatches(s)) {
      final id = m.group(1);
      if (id != null && seen.add(id)) ids.add(id);
    }
    _guardCache(_idsCache);
    _idsCache[s] = List<String>.unmodifiable(ids);
    return _idsCache[s]!;
  }

  /// 把 Markdown+LaTeX 粗略转成纯文本预览（用于 maxLines:1 折叠标题等无法放富文本处）。
  static String plainPreview(String s, {int maxLen = 60}) {
    final key = '$maxLen\u0000$s';
    final hit = _previewCache[key];
    if (hit != null) return hit;
    var t = s
        .replaceAll(chunkTagRegex, '') // 折叠预览不显示溯源编号
        .replaceAll(RegExp(r'`{1,3}'), '')
        .replaceAll(RegExp(r'\${1,2}'), '') // 去掉 $ / $$ 定界符
        .replaceAll(RegExp(r'\\[a-zA-Z]+'), '') // 去掉 \frac \int 等命令名
        .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '')
        .replaceAll(RegExp(r'^\s{0,3}[-*+]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s{0,3}\d+\.\s+', multiLine: true), '')
        .replaceAll(RegExp(r'[*_~]{1,3}'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (t.length > maxLen) t = '${t.substring(0, maxLen)}…';
    _guardCache(_previewCache);
    _previewCache[key] = t;
    return t;
  }

  /// 把 Markdown + LaTeX + 豁免标记转成适合朗读的纯文本（不截断）。
  static String toSpeech(String s) {
    final hit = _speechCache[s];
    if (hit != null) return hit;
    final t = s
        .replaceAll(chunkTagRegex, '') // 朗读不念「C H 减 M E ...」这类编号
        .replaceAll(_openExempt, '')
        .replaceAll(_closeExempt, '')
        .replaceAll(_openCritical, '')
        .replaceAll(_closeCritical, '')
        .replaceAll(RegExp(r'`{1,3}'), '')
        .replaceAll(RegExp(r'\$\$[\s\S]*?\$\$'), ' ')
        .replaceAll(RegExp(r'\$[^\$]*\$'), ' ')
        .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '')
        .replaceAll(RegExp(r'^\s{0,3}[-*+]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s{0,3}\d+\.\s+', multiLine: true), '')
        .replaceAll(RegExp(r'[*_~]{1,3}'), '')
        .replaceAll(RegExp(r'\|'), ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    _guardCache(_speechCache);
    _speechCache[s] = t;
    return t;
  }

  // 与 ExemptBlock 相同的标记常量
  static const _openExempt = '【反方观点·仅供批判】';
  static const _closeExempt = '【/反方观点】';
  static const _openCritical = '【批判对象·非借鉴】';
  static const _closeCritical = '【/批判对象】';

  /// Markdown 语法扩展是纯配置，全局复用一份（原来每条消息都重建列表）。
  static final md.ExtensionSet _extensionSet = md.ExtensionSet(
    [...md.ExtensionSet.gitHubFlavored.blockSyntaxes, LatexBlockSyntax()],
    [...md.ExtensionSet.gitHubFlavored.inlineSyntaxes, LatexInlineSyntax()],
  );

  /// 样式表按（颜色/字号/亮度）缓存：长会话里大量气泡共用，避免每次 build 重建。
  static final Map<String, MarkdownStyleSheet> _sheetCache = <String, MarkdownStyleSheet>{};

  @override
  Widget build(BuildContext context) {
    // 渲染前剥离内部溯源编码：AI 对话里不再出现 [CH-...] 编号。
    final clean = text.contains('[') ? stripChunkTags(text) : text;

    // 1) 把文本按「豁免标记」切段：普通段 或 豁免段
    final segs = <_Seg>[];
    int i = 0;
    while (i < clean.length) {
      final exO = clean.indexOf(_openExempt, i);
      final crO = clean.indexOf(_openCritical, i);
      int next = -1;
      bool critical = false;
      if (exO >= 0 && (crO < 0 || exO < crO)) {
        next = exO;
        critical = false;
      } else if (crO >= 0) {
        next = crO;
        critical = true;
      }
      if (next < 0) {
        _pushText(segs, clean.substring(i));
        break;
      }
      if (next > i) _pushText(segs, clean.substring(i, next));
      final open = critical ? _openCritical : _openExempt;
      final close = critical ? _closeCritical : _closeExempt;
      final closeIdx = clean.indexOf(close, next);
      final innerEnd = closeIdx >= 0 ? closeIdx : clean.length;
      final inner = clean.substring(next + open.length, innerEnd);
      segs.add(_Seg(kind: critical ? _Kind.critical : _Kind.exempt, content: inner));
      i = closeIdx >= 0 ? closeIdx + close.length : clean.length;
    }

    // 2) 组装：普通段 → MarkdownBody；豁免段 → 彩色标注框 + 框内同样 Markdown 渲染
    final widgets = <Widget>[];
    for (final s in segs) {
      if (s.kind == _Kind.text) {
        final d = s.content.trim();
        if (d.isEmpty) continue;
        widgets.add(_md(context, d));
      } else {
        final d = s.content.trim();
        if (d.isEmpty) continue;
        widgets.add(_exemptBox(context, d, critical: s.kind == _Kind.critical));
      }
    }
    if (widgets.isEmpty) return const SizedBox.shrink();
    if (widgets.length == 1) return widgets.first;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  void _pushText(List<_Seg> segs, String s) {
    if (s.isEmpty) return;
    if (segs.isNotEmpty && segs.last.kind == _Kind.text) {
      segs.last.content += s;
    } else {
      segs.add(_Seg(kind: _Kind.text, content: s));
    }
  }

  /// 豁免段 / 批判对象段的彩色标注框（视觉沿用原 ExemptBlock，框内正文支持 Markdown + 数学）。
  Widget _exemptBox(BuildContext context, String inner, {required bool critical}) {
    final accent = Color(critical ? 0xFFB45309 : 0xFFB91C1C);
    final bodyColor = Color(critical ? 0xFF78350F : 0xFF7F1D1D);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Color(critical ? 0xFFFEF3C7 : 0xFFFEE2E2),
        border: Border(left: BorderSide(color: Color(critical ? 0xFFF59E0B : 0xFFE11D48), width: 3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, size: 13, color: accent),
              const SizedBox(width: 4),
              Text(
                critical ? '批判对象 · 非借鉴' : '反方观点 · 仅供批判',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: accent,
                  fontFamily: 'Deng',
                  fontFamilyFallback: const ['Deng', 'Roboto', 'WarnSym'],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _md(context, inner, color: bodyColor, fontSize: 13),
        ],
      ),
    );
  }

  Widget _md(BuildContext context, String data, {Color? color, double fontSize = 14}) {
    final fg = color ?? baseColor;
    final key = '${fg.toARGB32()}-$fontSize-${Theme.of(context).brightness.index}';
    final sheet = _sheetCache.putIfAbsent(key, () {
      final base = TextStyle(
        fontSize: fontSize,
        height: 1.55,
        color: fg,
        fontFamily: 'Deng',
        fontFamilyFallback: const ['Deng', 'Roboto', 'WarnSym'],
      );
      return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: base,
        pPadding: EdgeInsets.zero,
        a: base.copyWith(
            color: AppColors.brand,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: AppColors.brand.withValues(alpha: 0.55)),
        em: base.copyWith(fontStyle: FontStyle.italic),
        strong: base.copyWith(fontWeight: FontWeight.w700),
        code: base.copyWith(
          fontFamily: 'Roboto',
          fontFamilyFallback: const ['Roboto', 'Deng'],
          backgroundColor: AppColors.surface,
          fontSize: fontSize - 1,
        ),
        blockquote: base.copyWith(color: fg),
        blockquotePadding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        blockquoteDecoration: const BoxDecoration(
          color: Color(0x14D4A017),
          border: Border(left: BorderSide(color: AppColors.gold, width: 3)),
        ),
        listBullet: base,
        listIndent: 18,
        blockSpacing: 6,
        h1: base.copyWith(fontSize: fontSize + 4, fontWeight: FontWeight.w700, color: fg),
        h2: base.copyWith(fontSize: fontSize + 2, fontWeight: FontWeight.w700, color: fg),
        h3: base.copyWith(fontSize: fontSize + 1, fontWeight: FontWeight.w700, color: fg),
        h1Padding: EdgeInsets.zero,
        h2Padding: EdgeInsets.zero,
        h3Padding: EdgeInsets.zero,
        horizontalRuleDecoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.line, width: 1)),
        ),
      );
    });

    return MarkdownBody(
      data: data,
      selectable: true,
      fitContent: true,
      styleSheet: sheet,
      builders: {
        'latex': LatexElementBuilder(textStyle: sheet.p ?? TextStyle(color: fg)),
      },
      extensionSet: _extensionSet,
    );
  }
}

enum _Kind { text, exempt, critical }

class _Seg {
  _Kind kind;
  String content;
  _Seg({required this.kind, required this.content});
}
