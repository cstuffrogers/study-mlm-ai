// 备份提醒门禁：BackupReminder.overdue 的判定口径必须稳定。
//
// 为什么单独测：本机数据是唯一副本（allowBackup=false），提醒逻辑错了
// 要么永远不提醒（用户丢机清零），要么每次都弹（烦人）。纯函数 + 注入时间，
// 不依赖 SharedPreferences 实例，稳定可测。
import 'package:flutter_test/flutter_test.dart';

import 'package:marxism_reader/services/backup_reminder.dart';

void main() {
  const day = 24 * 60 * 60 * 1000;
  final now = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);

  group('BackupReminder.overdue', () {
    test('从未备份（null）→ 提醒', () {
      expect(BackupReminder.overdue(null, now: now), isTrue);
    });

    test('刚备份过（< 7 天）→ 不提醒', () {
      final last = now.millisecondsSinceEpoch - 1 * day;
      expect(BackupReminder.overdue(last, now: now), isFalse);
    });

    test('刚好 7 天 → 提醒（达到阈值）', () {
      final last = now.millisecondsSinceEpoch - 7 * day;
      expect(BackupReminder.overdue(last, now: now), isTrue);
    });

    test('6 天多（差一点不到 7 天）→ 不提醒', () {
      final last = now.millisecondsSinceEpoch - (7 * day - 1);
      expect(BackupReminder.overdue(last, now: now), isFalse);
    });

    test('远超 7 天（30 天）→ 提醒', () {
      final last = now.millisecondsSinceEpoch - 30 * day;
      expect(BackupReminder.overdue(last, now: now), isTrue);
    });

    test('未来时间戳（时钟回拨）→ 不提醒（不算逾期）', () {
      // 上次备份时间戳在未来（系统时钟回拨 / 异常写入），不该误判逾期。
      final last = now.millisecondsSinceEpoch + 1 * day;
      expect(BackupReminder.overdue(last, now: now), isFalse);
    });

    test('提醒阈值常量为 7 天', () {
      expect(BackupReminder.remindAfterDays, 7);
    });
  });
}
