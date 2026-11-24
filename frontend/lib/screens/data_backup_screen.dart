// 本机数据备份 / 恢复页。
//
// 为什么要它：应用内升级（APK 覆盖安装）本来就不会动本机数据——同包名 + 同签名即可。
// 真正的风险是「卸载重装 / 换手机 / 清应用数据」，以及将来某次改动不小心改了存储键。
// 这一页把数据摊开给你看，并能导出成 JSON 文件、换机后再灌回去。
//
// 安全口径：默认**不导出 API Key**（备份就是一串文本，容易外泄）；
// 恢复时保留本机已有的密钥，不会因为恢复备份把配好的大模型清掉。
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../offline/data_compat.dart';
import '../theme/app_theme.dart';

class DataBackupScreen extends StatefulWidget {
  const DataBackupScreen({super.key});

  @override
  State<DataBackupScreen> createState() => _DataBackupScreenState();
}

class _DataBackupScreenState extends State<DataBackupScreen> {
  Map<String, int> _stats = const {};
  bool _busy = false;
  String _preview = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await DataCompat.stats();
    if (!mounted) return;
    setState(() => _stats = s);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  String _ts() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  // ------------------------------------------------------------ 导出

  /// 导出为 JSON 文件，保存到应用文档目录。
  Future<void> _exportToFile() async {
    if (kIsWeb) {
      _toast('文件导出仅在移动端 APP 可用');
      return;
    }
    setState(() => _busy = true);
    try {
      final json = await DataCompat.exportJson();
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/xxmz_backup_${_ts()}.json');
      await file.writeAsString(json);
      if (!mounted) return;
      setState(() => _preview = json.length > 1200 ? '${json.substring(0, 1200)}…' : json);
      _toast('已保存到文件（${(json.length / 1024).toStringAsFixed(1)} KB）\n${file.path}');
    } catch (e) {
      _toast('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------ 导入

  /// 从文件恢复：列出文档目录下的备份文件，选择后合并恢复。
  Future<void> _importFromFile() async {
    if (kIsWeb) {
      _toast('文件导入仅在移动端 APP 可用');
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final files = dir.listSync()
        .map((e) => e as File)
        .where((f) => f.path.endsWith('.json') && f.path.contains('xxmz_backup'))
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    if (files.isEmpty) {
      _toast('本机文档目录下没有备份文件，请先「导出到文件」');
      return;
    }
    if (!mounted) return;
    final picked = await showDialog<File>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择备份文件'),
        content: SizedBox(
          height: 320,
          child: ListView(
            children: [
              for (final f in files)
                ListTile(
                  leading: const Icon(Icons.description_outlined, size: 22),
                  title: Text(f.path.split('/').last),
                  subtitle: Text('${(f.lengthSync() / 1024).toStringAsFixed(1)} KB'),
                  onTap: () => Navigator.pop(ctx, f),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ],
      ),
    );
    if (picked == null) return;
    final raw = await picked.readAsString();
    await _doImport(raw);
  }

  /// 共用的导入确认 + 执行逻辑。
  Future<void> _doImport(String raw) async {
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从备份恢复？'),
        content: const Text(
          '会把备份里的对话、学习记录、学情、勋章、笔记、书签、阅读进度合并进来。\n\n'
          '· 同名记录以备份为准；\n'
          '· 本机有、备份里没有的数据**不会被删除**；\n'
          '· 大模型 API Key 保留本机现值。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('合并恢复')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final counts = await DataCompat.importJson(raw);
      await _refresh();
      if (!mounted) return;
      final desc = counts.entries.map((e) => '${_label(e.key)} ${e.value}').join('、');
      _toast(desc.isEmpty ? '备份里没有可恢复的数据' : '已恢复：$desc');
    } on FormatException catch (e) {
      _toast('备份内容无法识别：${e.message}');
    } catch (e) {
      _toast('恢复失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _label(String key) => const {
        'off_dialogues': '对话',
        'off_attempts': '答题记录',
        'off_mastery': '掌握度',
        'off_progress': '章节进度',
        'off_tests': '测验记录',
        'off_settings': '设置项',
        'off_signals': '学情信号',
        'off_badges': '勋章',
        'reader_keys': '原文数据项',
        'tts_keys': '朗读设置',
      }[key] ??
      key;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本机数据'),
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _card(
            title: '升级不会清空这些数据',
            body: '应用内升级（覆盖安装新版本）不改动本机数据：包名与签名保持不变，'
                '对话记录、学习记录、学情、勋章、原文笔记、阅读进度、大模型设置都会原样保留。\n\n'
                '会丢数据的情况只有三种：卸载重装、换设备、清除应用数据。'
                '这三种情况用下面的「备份」把数据搬过去。',
          ),
          const SizedBox(height: 12),
          _statCard(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _exportToFile,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('导出到文件'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _importFromFile,
                  icon: const Icon(Icons.restore),
                  label: const Text('从文件恢复'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '备份是一段 JSON 文件，含对话、答题记录、掌握度、章节进度、勋章、原文笔记/书签/划线、'
            '阅读进度与设置。朗读风格预设、语音包也会一并备份。出于安全，API Key 不进备份——换机恢复后请到大模型配置页重填一次。\n\n'
            '「导出到文件」保存在应用文档目录下（xxmz_backup_日期_时间.json），'
            '换机时把该文件传到新手机即可用「从文件恢复」灌回。',
            style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.ink500),
          ),
          if (_preview.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('最近一次导出的开头',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink700)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _preview,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card({required String title, required String body}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink700)),
            const SizedBox(height: 8),
            Text(body,
                style: const TextStyle(fontSize: 13, height: 1.7, color: AppColors.ink500)),
          ],
        ),
      );

  Widget _statCard() {
    final rows = <(String, int)>[
      ('对话', _stats['dialogues'] ?? 0),
      ('消息', _stats['messages'] ?? 0),
      ('答题记录', _stats['attempts'] ?? 0),
      ('掌握度节点', _stats['mastery_nodes'] ?? 0),
      ('勋章', _stats['badges'] ?? 0),
      ('原文笔记', _stats['notes'] ?? 0),
      ('划线', _stats['highlights'] ?? 0),
      ('书签', _stats['bookmarks'] ?? 0),
      ('读过的原著', _stats['read_works'] ?? 0),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('本机现有数据',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in rows)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.brandSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${r.$1} ${r.$2}',
                      style: TextStyle(fontSize: 12.5, color: AppColors.brandDeep)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
