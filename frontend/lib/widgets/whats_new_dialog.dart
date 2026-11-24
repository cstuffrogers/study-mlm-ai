// 「本次更新内容」提示框 —— 升级后第一次启动时弹一次，说清这版改了什么。
//
// 设计口径（改动前先读）：
//  · 内容取自 lib/config/changelog.dart（写进安装包，离线可看），不联网；
//  · **一个版本只弹一次**：看过就把版本号记进 SharedPreferences
//    （services/changelog_seen.dart），之后每次启动都不再打扰；
//  · **全新安装不弹**：刚装上的人没有「更新」可言，只登记一下，免得下次启动
//    莫名弹出「本次更新内容」；
//  · 跨版本升级（1.4.16 → 1.4.19）把中间几版一并展示，他确实错过了；
//  · 弹框只读：没有「立即更新」「去下载」之类按钮，更新是另一套流程
//    （services/app_update.dart + update_dialog.dart），别在这里混着来。
import 'package:flutter/material.dart';

import '../config/changelog.dart';
import '../services/changelog_seen.dart';
import '../theme/app_theme.dart';

/// 启动时调用：该弹就弹，弹完登记。返回的 Future 在弹框关闭后完成。
///
/// [freshInstall]：本次是全新安装（本机此前没有任何数据）。真则只登记不弹。
Future<void> maybeShowWhatsNew(
  BuildContext context, {
  bool freshInstall = false,
}) async {
  final cur = currentChangelog;
  // 没给当前版本写说明就不弹（发布前有门禁拦，运行期不打扰用户）
  if (cur == null) return;
  final seen = await ChangelogSeen.read();
  if (seen == normalizeVersion(cur.version)) return;
  if (freshInstall) {
    await ChangelogSeen.markSeen(cur.version);
    return;
  }
  if (!context.mounted) return;
  final entries = changelogSince(seen);
  if (entries.isEmpty) {
    await ChangelogSeen.markSeen(cur.version);
    return;
  }
  await showWhatsNewDialog(context, entries: entries);
  await ChangelogSeen.markSeen(cur.version);
}

/// 只看不登记（「关于」页里主动点开时用，不影响启动时那次登记）。
Future<void> showWhatsNewDialog(
  BuildContext context, {
  required List<ChangelogEntry> entries,
  String title = '本次更新内容',
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _WhatsNewDialog(entries: entries, title: title),
  );
}

/// 「关于」页入口：显示全部历史版本的更新说明。
Future<void> showAllChangelog(BuildContext context) {
  return showWhatsNewDialog(
    context,
    entries: kChangelog,
    title: '更新说明',
  );
}

class _WhatsNewDialog extends StatelessWidget {
  const _WhatsNewDialog({required this.entries, required this.title});

  final List<ChangelogEntry> entries;
  final String title;

  @override
  Widget build(BuildContext context) {
    final multi = entries.length > 1;
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.new_releases_outlined, size: 20, color: AppColors.brand),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: const TextStyle(fontSize: 17))),
      ]),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (multi)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '你跨了几个版本，下面是这几版的变化（共 ${entries.length} 个版本）。',
                    style: const TextStyle(
                        fontSize: 12, height: 1.5, color: AppColors.ink400),
                  ),
                ),
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) const Divider(height: 22),
                _entryBlock(entries[i]),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    );
  }

  Widget _entryBlock(ChangelogEntry e) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'v${e.version}',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brand),
            ),
          ),
          const SizedBox(width: 8),
          Text(e.date,
              style: const TextStyle(fontSize: 11.5, color: AppColors.ink400)),
        ]),
        const SizedBox(height: 8),
        for (final g in e.groups) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(g.title,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink700)),
          ),
          for (final item in g.items)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6, right: 6),
                  child: SizedBox(
                    width: 4,
                    height: 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          color: AppColors.ink400, shape: BoxShape.circle),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(item,
                      style: const TextStyle(
                          fontSize: 12.5, height: 1.55, color: AppColors.ink700)),
                ),
              ]),
            ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}
