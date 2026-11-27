// 「上次备份是什么时候」——只记一个时间戳，不采集任何别的信息。
//
// 为什么要它：本机数据是唯一副本（AndroidManifest 里 allowBackup=false，因为数据
// 里含用户配的大模型 API Key，不能被系统自动备份）。丢机 / 卸载重装 / 清应用数据
// 都会让全部学习记录清零。所以导出备份是用户自己要做的事，App 定期提醒一下。
//
// 放在 SharedPreferences：启动即读，比 LocalDb 早；备份时间戳属于本机界面状态，
// 不是学习数据，**不随备份导入**到别的设备（换机后从零开始提醒）。
import 'package:shared_preferences/shared_preferences.dart';

import '../offline/local_store_keys.dart';

class BackupReminder {
  BackupReminder._();

  static const String _key = LocalStoreKeys.backupLastTs;

  /// 超过这个天数没导出，就在首页提示（与「每周备份一次」的直觉对齐）。
  static const int remindAfterDays = 7;

  /// 上次成功导出的时间戳（毫秒）；从未导出为 null。
  static Future<int?> readLastTs() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.trim().isEmpty) return null;
    return int.tryParse(raw.trim());
  }

  /// 登记「刚刚成功导出了备份」。
  static Future<void> markExported() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, DateTime.now().millisecondsSinceEpoch.toString());
  }

  /// 纯函数：给定「上次备份时间戳（毫秒，null=从未备份）」与当前时刻，
  /// 判断是否该提醒。可注入 [now] 便于测试，默认取系统时间。
  static bool overdue(int? lastTsMs, {DateTime? now}) {
    final t = now ?? DateTime.now();
    if (lastTsMs == null) return true; // 从未备份 → 提醒
    return t.millisecondsSinceEpoch - lastTsMs >=
        remindAfterDays * 24 * 60 * 60 * 1000;
  }

  /// 供测试/调试：清掉登记（重置为「从未备份」）。
  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key);
  }
}
