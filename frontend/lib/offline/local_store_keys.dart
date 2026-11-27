// 本机数据存储键的**唯一登记处**。
//
// 为什么单列一个文件：这些字符串一旦随版本发布，就等于用户数据的地址。
// 改一个字母 = 老用户的数据还躺在旧键里，新版本读不到 → 表现为「升级后笔记/记录没了」。
// 因此：
//   · 任何业务代码必须从这里取键，不准再写字面量；
//   · 键名改动必须先加迁移（见 data_compat.dart），并补回归测试；
//   · 只许新增键，不许重命名既有键。
class LocalStoreKeys {
  LocalStoreKeys._();

  // —— LocalDb 七份文档（学情 / 记录 / 对话 / 设置）——
  /// 掌握度：routeId -> {nodeId: 记录}
  static const String mastery = 'off_mastery';

  /// 章节进度：routeId -> {sectionId: 记录}
  static const String progress = 'off_progress';

  /// 答题流水（列表）
  static const String attempts = 'off_attempts';

  /// 章节测验记录：testId -> 记录
  static const String tests = 'off_tests';

  /// 对话记录：dialogueId -> {…, messages: []}
  static const String dialogues = 'off_dialogues';

  /// 设置（当前路线、阅读偏好、大模型 API 配置、数据版本…）
  static const String settings = 'off_settings';

  /// 学情信号（对话 / 费曼）
  static const String signals = 'off_signals';

  /// 勋章授予记录：badgeId -> {award_id, badge_id, awarded_at, source_event, read_flag}
  static const String badges = 'off_badges';

  // —— 朗读设置（SharedPreferences 直读，早于 LocalDb 初始化）——
  /// 朗读风格预设 id（见 services/tts_settings.dart::TtsPresets）
  static const String ttsPreset = 'off_tts_preset';

  /// 选中的系统语音包名（'' = 自动优选）
  static const String ttsVoice = 'off_tts_voice';

  // —— 版本更新说明（SharedPreferences，早于 UI）——
  /// 已经看过更新说明的客户端版本（如 `1.4.19`）。
  /// 只用来决定「升级后第一次启动要不要弹本次更新内容」；
  /// 不存在 = 还没弹过（或老版本升上来、本功能上线前的安装）。
  static const String changelogSeen = 'off_changelog_seen';

  /// 上次成功导出备份的时间戳（毫秒，见 services/backup_reminder.dart）。
  /// 用于「N 天没备份就提醒导出」：本机数据是唯一副本（allowBackup=false），
  /// 丢了就全没，所以要定期提示用户导出一份 JSON 落盘。
  static const String backupLastTs = 'off_backup_last_ts';

  /// LocalDb 全部文档键，按 flush 顺序
  static const List<String> docs = [
    mastery,
    progress,
    attempts,
    tests,
    dialogues,
    settings,
    signals,
    badges,
  ];

  // —— 原文阅读器：每部著作一份 ——
  /// 前缀：`reader_<著作名>_<后缀>`
  static const String readerPrefix = 'reader_';

  /// 字号
  static const String readerFontSize = 'fs';

  /// 书签
  static const String readerBookmarks = 'bm';

  /// 原文笔记
  static const String readerNotes = 'nt';

  /// 划线
  static const String readerHighlights = 'hl';

  /// 上次阅读页（原文浏览记录）
  static const String readerLastPage = 'last';

  static const List<String> readerSuffixes = [
    readerFontSize,
    readerBookmarks,
    readerNotes,
    readerHighlights,
    readerLastPage,
  ];

  static String reader(String work, String suffix) =>
      '$readerPrefix${work}_$suffix';

  /// 从完整键还原著作名（备份导入 / 体检用）。
  static String? readerWorkOf(String key) {
    if (!key.startsWith(readerPrefix)) return null;
    for (final s in readerSuffixes) {
      final tail = '_$s';
      if (key.endsWith(tail)) {
        final w = key.substring(readerPrefix.length, key.length - tail.length);
        return w.isEmpty ? null : w;
      }
    }
    return null;
  }

  // —— 跨文档冗余副本（独立键，不属于七份文档）——
  /// 大模型配置的**冗余副本**（JSON 字符串，与 settings 里的 llm_config 同构）。
  ///
  /// 为什么需要：API Key 只存在 `off_settings` 这一份文档里，而这整份文档是
  /// 「一次读出 + 整篇回写」的。一旦这份 JSON 读坏了（升级装包时进程被杀、
  /// 写到一半被截断），LocalDb 会把它隔离到 `off_settings_corrupt` 并按空数据
  /// 启动——结果是掌握/进度/对话都还在，**只有设置类（AI 配置）没了**，
  /// 用户看到的就是「更新后 AI 用不了，又得重新配置一遍」（D174）。
  /// 有了副本，读不到主存储时能从副本自愈，不用用户重填。
  static const String llmConfigShadow = 'off_llm_config_shadow';

  /// 全部「独立小键」（LocalDb 启动时会一次性读进内存）
  static const List<String> extras = [llmConfigShadow];

  // —— 其它 ——
  /// 学习记录同步队列
  static const String syncQueue = 'sync_queue_v1';

  /// 损坏文档隔离键：`<文档键>_corrupt`。
  /// LocalDb 读到解析失败的文档时，把原文原样存到这里，内存按空数据运行，
  /// 保证坏数据可找回（不影响七份文档键本身的备份/恢复面）。
  static String corruptKey(String docKey) => '${docKey}_corrupt';
}
