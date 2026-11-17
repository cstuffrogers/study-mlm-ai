// 关于页元信息（编译期默认值）——避免运行时在不同平台读不到 pubspec.yaml。
//
// 口径说明（务必如实，不要拿第三方链接/署名冒充本项目）：
// · appName / productName / tagline 取自 lib/main.dart:32、web/manifest.json、根 README.md:1。
// · clientVersion 取自 pubspec.yaml，**改版本号时两处必须同步**（有测试盯着，见 version_sync_test.dart）；
//   serverVersion 取自离线内容资源导出版本（沿用 0.1.0-mvp）。二者是两套编号体系，页面分别标注。
// · githubUrl / releasesUrl / author：仓库已上线，地址**固定**在这里（2026-11-16 建库）。
//   用户仍可在「关于」页点「编辑项目信息」做本机覆盖（用于 fork 后指向自己的仓库）。
// · 仓库：https://github.com/cstuffrogers/study-mlm-ai （public，默认分支 main）
class AppMeta {
  static const appName = '唯物 · 马哲精读';
  static const productName = '正统马哲深度学习系统';
  static const tagline = '三路线 · 逐章精读 · AI 测试';
  static const clientVersion = '1.3.9+20';
  static const serverVersion = '0.1.0-mvp';
  static const packageName = 'marxism_reader';

  /// 客户端版本 + 构建号（与 pubspec.yaml 的 `1.0.0+1` 对应）
  static String get clientVersionLabel {
    final v = clientVersion.split('+');
    return v.length == 2 ? '${v[0]} (build ${v[1]})' : clientVersion;
  }

  /// 项目 GitHub 仓库地址（权威值，已固定）。
  static const githubUrl = 'https://github.com/cstuffrogers/study-mlm-ai';

  /// 最新版本下载页（GitHub Releases）。关于页「下载最新安卓版」按钮指向这里。
  static const releasesUrl =
      'https://github.com/cstuffrogers/study-mlm-ai/releases/latest';

  /// 作者 / 版权署名（与 LICENSE 的 `Copyright (c) 2026 xxmz contributors` 一致）。
  static const author = 'xxmz contributors';

  /// 软件许可（只覆盖代码与自撰辅助材料，不覆盖原著正文与译文）。
  static const licenseName = 'MIT';

  /// 正文权利声明的文件名（仓库根目录），关于页给出仓库内路径提示。
  static const contentNoticeDoc = 'CONTENT-NOTICE.md';

  /// 技术栈与部署说明（来自 README.md，用于「关于」页如实描述系统构成）
  static const stack = 'Flutter 单机应用 · 内置 229 部原著正文库（无后端、无网络依赖）';
  static const localUrls = '全部数据随安装包内置；学习记录只保存在本机';

  // ---- 合规与运营者信息（占位，发布前必须由运营者填真实值）----
  // 应用商店审核要求「隐私政策」可打开且写明运营者与联系方式；
  // 未填时「法律与隐私」页会如实显示「未配置」并给出明显的待办提示，不编造。

  /// 运营者 / 开发者主体名称（个人可用真实姓名或工作室名）。
  static const operatorName = '';

  /// 运营者联系邮箱（用于隐私与内容投诉）。
  static const operatorEmail = '';

  /// 工信部 APP 备案号（形如「京ICP备00000000号-1A」）。
  static const appFilingNo = '';

  /// 内容数据版权与来源说明版本号（改内容库时同步递增，便于追溯）。
  static const contentNoticeVersion = '2026-11-16';

  /// 内置原著正文部数（= sources/texts/*.txt 书目数，改内容库时同步）。
  static const contentWorkCount = 229;

  /// 作**仍处于著作权保护期内**的部数（截至 2026-11-16）。
  ///
  /// 口径：毛泽东（1976-09-09 逝世，48 部）+ 周恩来（1976-01-08 逝世，27 部）。
  /// 按《著作权法》一般作品「作者终生 + 死后 50 年、截止于第 50 年 12 月 31 日」，
  /// 两人作品均于 **2026-12-31 届满**，即 2027-01-01 起进入公有领域。
  /// 到时把本常量改为 0，并同步更新「法律与隐私」页的表述。
  static const copyrightPendingCount = 75;

  static const prefGithubKey = 'about_github_url';
  static const prefAuthorKey = 'about_author';

  /// 运营者信息是否已补齐（未补齐时法律页顶部显示待办横幅）。
  static bool get operatorConfigured =>
      operatorName.trim().isNotEmpty && operatorEmail.trim().isNotEmpty;

  /// 链接可展示/可打开的门槛：必须是真实 http(s) URL，且不能是占位示例。
  static bool isValidUrl(String s) {
    final u = Uri.tryParse(s.trim());
    if (u == null || !u.hasScheme || (u.scheme != 'http' && u.scheme != 'https')) {
      return false;
    }
    return u.host.isNotEmpty &&
        !u.host.contains('<') &&
        !s.contains('example.com');
  }
}
