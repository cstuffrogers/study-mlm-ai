// 原著浏览页 — 一本本书的卡片墙 + 按书名/作者搜索。
//
// 交互与「查看原文」完全一致：点任一卡片直接进入 WorkReaderScreen（分页阅读器：
// 翻页 / 目录 / 字号 / 划线 / 笔记 / 书签 / 进度记忆 / AI 精读），不再有中间的分片列表。
//
// 搜索：书名、作者、简称都能搜，多个词按「与」匹配（如「毛泽东 矛盾」）；
// 作者筛选条按著作数排序，点一下只看这位作者的著作。
// 作者来自构建期导出的 meta.json（源自 BOOKS 登记表），查不到就显示「作者未标注」——不猜、不编。
import 'package:flutter/material.dart';

import '../offline/offline_content.dart';
import '../services/content_service_api.dart';
import '../theme/app_theme.dart';
import '../widgets/anim.dart';
import '../widgets/book_icon.dart';
import 'work_reader_screen.dart';

class SourceBrowserScreen extends StatefulWidget {
  const SourceBrowserScreen({super.key});

  @override
  State<SourceBrowserScreen> createState() => _SourceBrowserScreenState();
}

class _SourceBrowserScreenState extends State<SourceBrowserScreen> {
  List<Map<String, dynamic>> _works = const [];
  String _query = '';
  String _author = '';
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 先拿后端清单；后端不可达时退回内置离线清单（离线包里带了作者/段数），
      // 保证「原著浏览」在单机 App / 后端未起时也能打开。
      var works = await ContentApi().worksWithMeta();
      if (works.isEmpty) {
        await OfflineContent.ensureMeta();
        works = OfflineContent.works;
      }
      if (!mounted) return;
      setState(() {
        _works = works;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _authorOf(Map<String, dynamic> w) {
    final a = '${w['author'] ?? ''}'.trim();
    return a.isEmpty ? '作者未标注' : a;
  }

  /// 「与」匹配：所有词都要在书名或作者里出现，忽略空白与英文大小写。
  bool _matches(Map<String, dynamic> w, String query) {
    if (query.trim().isEmpty) return true;
    final hay = '${w['work']} ${w['author'] ?? ''}'.toLowerCase();
    return query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .every(hay.contains);
  }

  List<Map<String, dynamic>> get _filtered => _works
      .where((w) => _matches(w, _query))
      .where((w) => _author.isEmpty || _authorOf(w) == _author)
      .toList();

  /// 作者 → 著作数（按著作数降序、名字本地序），用于作者筛选条
  List<MapEntry<String, int>> get _authors {
    final count = <String, int>{};
    for (final w in _works) {
      final a = _authorOf(w);
      count[a] = (count[a] ?? 0) + 1;
    }
    final list = count.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    return list;
  }

  int _chunksOf(Map<String, dynamic> w) =>
      (w['chunk_count'] as num?)?.toInt() ?? 0;

  void _open(Map<String, dynamic> w) {
    final name = '${w['work']}';
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WorkReaderScreen(work: name, title: name),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('原著浏览')),
      body: _error != null
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('加载失败：$_error',
                  style: const TextStyle(color: AppColors.ink500)),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: _load, child: const Text('重试')),
            ]))
          : _loading && _works.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  AnimatedEntrance(child: _searchBar()),
                  Expanded(child: _grid()),
                ]),
    );
  }

  Widget _searchBar() {
    final hit = _filtered;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      color: AppColors.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _searchCtrl,
          textInputAction: TextInputAction.search,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: '搜书名或作者，如「毛泽东」「矛盾论」',
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: '清空',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                  ),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: const BorderSide(color: AppColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: const BorderSide(color: AppColors.line),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _authorChip('全部作者', '', count: _works.length),
              for (final e in _authors)
                _authorChip(e.key, e.key, count: e.value),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _query.trim().isEmpty && _author.isEmpty
              ? '共 ${_works.length} 部著作 · 点书卡进入阅读'
              : '命中 ${hit.length} 部著作 · '
                  '${hit.fold<int>(0, (s, w) => s + _chunksOf(w))} 段原文',
          style: const TextStyle(fontSize: 11.5, color: AppColors.ink400),
        ),
      ]),
    );
  }

  Widget _authorChip(String label, String value, {required int count}) {
    final on = _author == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text('$label · $count',
            style: TextStyle(
                fontSize: 11.5, color: on ? Colors.white : AppColors.ink700)),
        selected: on,
        selectedColor: AppColors.brand,
        backgroundColor: Colors.white,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onSelected: (_) => setState(() => _author = value),
      ),
    );
  }

  Widget _grid() {
    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.search_off_rounded, size: 34, color: AppColors.ink400),
          const SizedBox(height: 8),
          Text('没有匹配「${_query.trim()}${_author.isEmpty ? '' : ' · $_author'}」的著作',
              style: const TextStyle(color: AppColors.ink500, fontSize: 13)),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              _searchCtrl.clear();
              setState(() {
                _query = '';
                _author = '';
              });
            },
            child: const Text('清空条件'),
          ),
        ]),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 20),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (c, i) => _bookRow(items[i]),
    );
  }

  /// 一部书一行：小书图标 + 书名 + 作者 · 段数 + 箭头。
  ///
  /// 演进：红书封（大色块）→ 两列网格行卡（177×139，一屏只放得下 6~8 部）
  /// → 现在单列细行（约 58px 高，一屏 10 部以上）。122 部著作看的是
  /// 「找书」而不是「逛封面」，所以密度优先：图标只做身份提示，不做装饰块。
  Widget _bookRow(Map<String, dynamic> w) {
    final name = '${w['work']}';
    final count = _chunksOf(w);
    final isSource = count > 0;
    final accent = _accentOf(name);
    // 这本书在学习路线里出现在几章（反向索引）：让「只挂在延伸阅读」的书
    // 也能被认出来有路径，而不是一堆找不到入口的名著。
    final secCount = OfflineContent.sectionsOfWork(name).length;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(w),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(children: [
            BookIcon(size: 17, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_authorOf(w)} · ${isSource ? '$count 段原文' : '仅导读'}'
                    '${secCount > 0 ? ' · $secCount 章' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isSource ? AppColors.ink400 : AppColors.warning,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.ink400),
          ]),
        ),
      ),
    );
  }

  /// 书脊色：按书名稳定取色（同一部书每次都是同一色，不随排序跳变）。
  /// 只在品牌红与中性暖调之间取，避免彩色杂牌感。
  static const _accents = <Color>[
    AppColors.brand,
    Color(0xFF9E1520),
    Color(0xFFB45309),
    Color(0xFF88613D),
    Color(0xFF6B5D59),
  ];

  Color _accentOf(String name) {
    if (name.isEmpty) return _accents.first;
    var h = 0;
    for (final u in name.codeUnits) {
      h = (h * 31 + u) & 0x7fffffff;
    }
    return _accents[h % _accents.length];
  }
}
