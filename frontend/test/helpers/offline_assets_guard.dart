// 离线数据的可用性探测（测试专用）。
//
// 为什么需要它：离线数据 `frontend/assets/offline/` 随仓库分发
// （其中 chunks.json 含全部 23,085 段原文，正文权利状态见 CONTENT-NOTICE.md），
// 但有人可能只取代码、或删掉数据只跑纯离线逻辑；那时依赖它的测试会整片报错——
// 看起来像项目坏了，实际只是缺数据。
//
// 用法：在测试文件 main() 的开头调用
//   if (skipWithoutOfflineAssets()) return;
// 无数据时该文件只报一条 skip（带补齐指引），其余测试不注册。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 离线数据是否就位（flutter test 的工作目录是 frontend/）。
bool get hasOfflineAssets =>
    File('assets/offline/knowledge.json').existsSync() ||
    File('assets/offline/meta.json').existsSync();

/// 无离线数据时注册一条 skip 并返回 true（调用方应直接 `return`）。
bool skipWithoutOfflineAssets() {
  if (hasOfflineAssets) return false;
  test(
    '（跳过）需要 assets/offline 离线数据',
    () {},
    skip: '未发现 assets/offline/ 离线数据，需自行生成：'
        '放入 sources/texts/*.txt 后运行 python scripts/export_offline_assets.py'
        '（详见 README「原著正文数据（克隆后必读）」）',
  );
  return true;
}
