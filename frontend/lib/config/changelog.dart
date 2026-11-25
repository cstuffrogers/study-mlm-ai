// 版本更新说明（changelog）——「本次更新内容」的**唯一数据源**。
//
// 为什么要写在代码里、不从网上抓：
//  · 单机版默认无网络，更新后第一次启动必须能立刻说出「这次更新了什么」，
//    不能等联网、也不能依赖 GitHub 能不能连上；
//  · 界面里显示的内容要和实际发的包对得上，写进安装包最可靠。
//
// 口径（改动前先读）：
//  · `kChangelog` **最新一版放第一个**，`version` 只写 `1.4.19` 这种三段式，
//    不带 `v`、不带 `+40`（构建号）；日期写 `YYYY-MM-DD`（发版当天）；
//  · 新增版本号时**必须先在这里补一条**——有门禁盯着
//    （test/d165_changelog_test.dart 会比对 AppMeta.clientVersion）；
//  · 文案写给用户看：说清「哪里变了、对他有什么用」，别写提交信息里的类名/文件名。
//
// 与远端的关系：`services/app_update.dart` 从 GitHub Release 抓的是「别人发的新版本说明」，
// 用于更新提示框；这里是**已经装上的这个版本**说明。两者互不替代。
import 'app_meta.dart';

class ChangelogGroup {
  const ChangelogGroup(this.title, this.items);

  /// 分组标题：新增 / 修复 / 变化
  final String title;

  /// 分组成员，每条一句话
  final List<String> items;
}

class ChangelogEntry {
  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.groups,
  });

  /// 三段式版本号，如 `1.4.19`（不带 `v` / `+构建号`）
  final String version;

  /// 发版日期 `YYYY-MM-DD`
  final String date;

  final List<ChangelogGroup> groups;

  /// 条目数（0 视为「没写」，门禁会拦）
  int get itemCount => groups.fold(0, (n, g) => n + g.items.length);

  String get label => 'v$version · $date';
}

/// 更新说明正文。**最新版本在最前面。**
const List<ChangelogEntry> kChangelog = [
  ChangelogEntry(
    version: '1.4.24',
    date: '2026-11-25',
    groups: [
      ChangelogGroup('修复', [
        '「该复习了 · 抗遗忘」里「建议巩固」那几项，点「去做练习」以前跳到的是「深入学习」导读页——'
            '一个只读的介绍页，还得自己往下翻才找到「开始章节测试」。现在直接进该知识点的章节测试出题；'
            '做完返回会自动刷新复习队列。',
      ]),
      ChangelogGroup('变化', [
        '该按钮改名为「去做巩固题」，条目说明改为「已掌握、不到期；进本章测试做几道题巩固」，'
            '不再写成「跨知识点混合练习」（实际出的是该章题库，按知识点交错排题）。',
      ]),
    ],
  ),
  ChangelogEntry(
    version: '1.4.23',
    date: '2026-11-25',
    groups: [
      ChangelogGroup('修复', [
        '选中一段原文后点「对话」，以前会替你先发一句「这段在说什么？」——你还没输入提示词，'
            'AI 就已经开始回答了。现在改为：选中的原句挂到输入框上方（提示「已带入你选的原句」），'
            '等你打完自己的问题，再连同这句原文一起发给 AI；不想带就点提示上的 ×。',
        '「释义 / 追问 / 辩难 / 关联」仍是一点即发（这几枚本来就是「就这段怎么展开」的一次性指令），'
            '不受此次改动影响。',
      ]),
      ChangelogGroup('变化', [
        '使用说明「选中文字 → AI 问答」一节同步改写：写清点「对话」只是带入原句、等你提问。',
      ]),
    ],
  ),
  ChangelogEntry(
    version: '1.4.22',
    date: '2026-11-25',
    groups: [
      ChangelogGroup('变化', [
        '选中原文后浮出的面板里，第一枚模式「普通对话」改名为「对话」（只有两个字更好认），'
            '点它仍然是带着这句原文直接提问。',
        '对话框输入框左侧那颗「对话」胶囊去掉了：输入框现在只剩输入与发送，'
            '进去就是普通提问，不用再看着一个点不动也切不了模式的标签。',
      ]),
      ChangelogGroup('修复', [
        '「该复习了 · 抗遗忘」卡片点了没反应 / 条目莫名消失：这张卡原来把两类东西混在一起，'
            '现在分成两张清单——「到期复习」问你还记得还是忘了，点完当场告诉你下次什么时候再复习；'
            '「建议巩固」是已掌握但还没到期的知识点，只给「去做混合练习」，不再要求你对没被提问的东西自评。',
        '复习自评失败（比如还没做过章节测验）以前什么都不说，现在会明说原因；'
            '接口出错也会提示「记录失败」，不再静默把条目吞掉。',
      ]),
    ],
  ),
  ChangelogEntry(
    version: '1.4.21',
    date: '2026-11-25',
    groups: [
      ChangelogGroup('新增', [
        '选中一段原文后浮出的小面板里多了「普通对话」：点它就把你选的那句一起带进提问，'
            '不用先打字再划重点，模型会围绕这句话回答。',
      ]),
      ChangelogGroup('变化', [
        '「选中文字 → AI 问答」面板现在有五枚模式（普通对话 / 释义 / 追问 / 辩难 / 关联），'
            '普通对话排在第一位，和对话框里打字是同一条路。',
        '对话框里依旧不能切换模式（固定普通对话）；要换方式就回到原文重新选中。',
        '使用说明重写「选中文字 → AI 问答」一节：写清五枚模式各给什么、'
            '普通对话带选区时到底发生了什么。',
      ]),
      ChangelogGroup('修复', [
        '正文与原著的用字统一（几十处异体字改正）后，内部校验恢复了「从原始资料一字不差复现正文」，'
            '这一版之后不会再出现「正文被悄悄改写」的隐患（不影响你读到的内容）。',
      ]),
    ],
  ),
  ChangelogEntry(
    version: '1.4.20',
    date: '2026-11-24',
    groups: [
      ChangelogGroup('新增', [
        '升级后第一次打开新版本，会自动弹一次「本次更新内容」，说清这版改了什么；'
            '看过就不再重复弹（同一个版本只打扰一次）。',
        '「功能中心 → 关于」多了一张「更新说明」卡片，随时能看本版说明；'
            '点「历史版本」可以翻之前几版的说明。',
      ]),
      ChangelogGroup('变化', [
        '跨好几个版本升级时，中间几版的内容会一并列出，不会只告诉你最新那一版。',
        '使用说明补充了「更新说明在哪看」的条目。',
      ]),
    ],
  ),
  ChangelogEntry(
    version: '1.4.19',
    date: '2026-11-24',
    groups: [
      ChangelogGroup('新增', [
        '连续朗读时可以暂停 / 继续了：原文页底栏「停止」左边多了暂停按钮，'
            '暂停只停当前这句的发声，读到哪儿、缓冲都留着，再点一下接着念。',
      ]),
      ChangelogGroup('修复', [
        '单机版勋章图标「同类的都长一样」：29 枚勋章以前只画出 7 种图标，现在各不相同。',
        '暂停后不会自己往下翻页了（以前暂停期间可能被误判成「这页读完」而错接下一页）。',
      ]),
      ChangelogGroup('变化', [
        '原文朗读的切段更细，暂停后从当前这一句接上，不再整页从头重念。',
        '底栏加控制按钮不改变底栏高度，排版不会因此重排（本页顶部不会再冒出上一页的文字）。',
        '使用说明补了暂停 / 继续的条目。',
      ]),
    ],
  ),
  ChangelogEntry(
    version: '1.4.18',
    date: '2026-11-24',
    groups: [
      ChangelogGroup('修复', [
        '错题本里题干与选项不再被截断，整题完整展示；右侧删除按钮与内容对齐。',
        '勋章图标重做：29 枚各有各的图形与发光效果，不再靠颜色区分。',
      ]),
      ChangelogGroup('变化', [
        '备份页去掉「复制到剪贴板」，只保留导入 / 导出（大文件贴剪贴板容易丢）。',
        '使用说明同步更新。',
      ]),
    ],
  ),
  ChangelogEntry(
    version: '1.4.17',
    date: '2026-11-24',
    groups: [
      ChangelogGroup('修复', [
        '修「勋章界面一片灰、打不开」：勋章列表少了排序字段导致页面构建失败，现在正常显示。',
      ]),
    ],
  ),
  ChangelogEntry(
    version: '1.4.16',
    date: '2026-11-24',
    groups: [
      ChangelogGroup('新增', [
        '题库扩充到 427 道、覆盖 106 个知识点，主观题按知识点配比出题。',
        '错题本可以删题：删掉的题不再出现在错题本，也不影响已记录的答题流水。',
      ]),
      ChangelogGroup('变化', [
        '极短的主观作答（十几字以内）不再误给分。',
        '使用说明同步更新。',
      ]),
    ],
  ),
];

/// 归一化版本号：去掉 `v` 前缀与 `+构建号`，只留 `1.4.19`。
String normalizeVersion(String raw) {
  var s = raw.trim();
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
  final plus = s.indexOf('+');
  if (plus >= 0) s = s.substring(0, plus);
  final dash = s.indexOf('-');
  if (dash >= 0) s = s.substring(0, dash);
  return s.trim();
}

/// 版本号拆成可比较的数字段；解析不出来时返回空。缺位按 0 补，故 `1.4` == `1.4.0`。
List<int> parseVersion(String raw) {
  final s = normalizeVersion(raw);
  if (s.isEmpty) return const [];
  final parts = s.split('.');
  final out = <int>[];
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null) return const [];
    out.add(n);
  }
  return out;
}

/// a 是否比 b 新（严格大于）。
bool isNewerVersion(String a, String b) {
  final x = parseVersion(a), y = parseVersion(b);
  if (x.isEmpty || y.isEmpty) return false;
  final n = x.length > y.length ? x.length : y.length;
  for (var i = 0; i < n; i++) {
    final l = i < x.length ? x[i] : 0;
    final r = i < y.length ? y[i] : 0;
    if (l != r) return l > r;
  }
  return false;
}

/// 按版本号查一条更新说明（`1.4.19` / `v1.4.19` / `1.4.19+40` 都能命中）。
ChangelogEntry? changelogFor(String version) {
  final key = normalizeVersion(version);
  if (key.isEmpty) return null;
  for (final e in kChangelog) {
    if (e.version == key) return e;
  }
  return null;
}

/// 当前安装的客户端版本对应的更新说明（没写则为 null）。
ChangelogEntry? get currentChangelog => changelogFor(AppMeta.clientVersion);

/// 「从 seen 版本之后」的所有说明，新→旧；seen 为空时只返回当前版本那一条。
///
/// 用途：用户跨版本升级（1.4.16 → 1.4.19）时，把中间几版的内容一并给他看，
/// 而不是只说最新那一版——他确实错过了中间的变化。
List<ChangelogEntry> changelogSince(String? seen) {
  final cur = currentChangelog;
  final out = <ChangelogEntry>[];
  if (seen == null || normalizeVersion(seen).isEmpty) {
    return cur == null ? out : [cur];
  }
  for (final e in kChangelog) {
    if (isNewerVersion(e.version, seen)) out.add(e);
  }
  // 比当前客户端还新的条目（本机装的是旧包）不展示，免得张冠李戴
  return out.where((e) => !isNewerVersion(e.version, AppMeta.clientVersion)).toList();
}
