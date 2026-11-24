// 「这个版本的更新说明看过没有」——只记一个版本号，不采集任何别的信息。
//
// 放在 SharedPreferences：启动即读，比 LocalDb 早，也不会被「恢复备份」带入
// 别的设备的记录（更新说明是否已读属于本机界面状态，不是学习数据）。
import 'package:shared_preferences/shared_preferences.dart';

import '../config/changelog.dart';
import '../offline/local_store_keys.dart';

class ChangelogSeen {
  ChangelogSeen._();

  static const String _key = LocalStoreKeys.changelogSeen;

  /// 已看过更新说明的版本（归一化后的三段式，如 `1.4.19`）；没看过为 null。
  static Future<String?> read() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.trim().isEmpty) return null;
    final v = normalizeVersion(raw);
    return v.isEmpty ? null : v;
  }

  /// 登记「本版本的更新说明已经看过」。
  static Future<void> markSeen(String version) async {
    final v = normalizeVersion(version);
    if (v.isEmpty) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, v);
  }

  /// 仅用于测试/调试：清掉登记。
  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key);
  }
}
