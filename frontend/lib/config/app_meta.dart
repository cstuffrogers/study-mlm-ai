// 关于页元信息（编译期默认值）——避免运行时在不同平台读不到 pubspec.yaml。
//
// 口径说明（务必如实，不要拿第三方链接/署名冒充本项目）：
// · appName / productName / tagline 取自 lib/main.dart:32、web/manifest.json、根 README.md:1。
// · clientVersion 取自 pubspec.yaml（1.2.0+9 单机版），**改版本号时两处必须同步**；
//   serverVersion 取自离线内容资源导出版本（沿用 0.1.0-mvp）。二者是两套编号体系，页面分别标注。
// · githubUrl / author：**项目自有文件里未找到权威值**（无 .git / remote、无 LICENSE、
//   无 author 字段；随包 marxist.space-master.zip 是第三方 ProleSoft 项目，不是本项目仓库）。
//   因此留空，由用户在「关于」页点「编辑项目信息」填入并保存；空值在页面上显示「未配置」。
// · 若日后拿到真实仓库地址/署名，直接把下面两个默认值改掉即可（用户本地覆盖优先）。
class AppMeta {
  static const appName = '唯物 · 马哲精读';
  static const productName = '正统马哲深度学习系统（xxmz）';
  static const tagline = '三路线 · 逐章精读 · AI 测试';
  static const clientVersion = '1.2.0+9';
  static const serverVersion = '0.1.0-mvp';
  static const packageName = 'marxism_reader';

  /// 客户端版本 + 构建号（与 pubspec.yaml 的 `1.0.0+1` 对应）
  static String get clientVersionLabel {
    final v = clientVersion.split('+');
    return v.length == 2 ? '${v[0]} (build ${v[1]})' : clientVersion;
  }

  /// 项目 GitHub 仓库地址。**未配置**：请在关于页「编辑项目信息」里填写，
  /// 或把本常量改成真实地址（例如 `https://github.com/owner/repo`）。
  static const githubUrl = '';

  /// 作者 / 版权 / 组织署名。**未声明**：请在关于页「编辑项目信息」里填写，
  /// 或把本常量改成真实署名（有 LICENSE 时同步补齐）。
  static const author = '';

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
