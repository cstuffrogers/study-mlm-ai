// 功能中心 →「关于」页：软件版本、项目地址（GitHub）、作者/版权等信息。
//
// 设计口径：
// · 版本/名称/技术栈等有权威来源，直接展示（见 lib/config/app_meta.dart）。
// · 仓库地址与署名已固定（lib/config/app_meta.dart 的 githubUrl / releasesUrl / author），
//   页面直接展示并可复制 / 跳转；「编辑项目信息」仅用于本机覆盖（fork 后指向自己的仓库）。
// · 打开外链复用项目已有的 services/open_url.dart 门面（Web 新标签页），不新增依赖。
// · 页面风格沿用功能中心 / LLM 配置页：AuroraBackground + GradientCard + 白卡。
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_meta.dart';
import '../services/open_url.dart';
import '../theme/app_theme.dart';
import '../widgets/anim.dart';
import '../widgets/guide_dialog.dart';
import 'legal_screen.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _github = AppMeta.githubUrl;
  String _author = AppMeta.author;

  final _formKey = GlobalKey<FormState>();
  final _githubCtrl = TextEditingController();
  final _authorCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _githubCtrl.dispose();
    _authorCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final g = sp.getString(AppMeta.prefGithubKey) ?? AppMeta.githubUrl;
      final a = sp.getString(AppMeta.prefAuthorKey) ?? AppMeta.author;
      if (!mounted) return;
      setState(() {
        _github = g;
        _author = a;
      });
    } catch (_) {
      // 非插件环境（如纯 VM 单测）：保留编译期默认值即可，不影响展示。
    }
  }

  Future<void> _persist(String github, String author) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(AppMeta.prefGithubKey, github);
      await sp.setString(AppMeta.prefAuthorKey, author);
    } catch (_) {
      // 本机偏好不可用时仅本次会话生效，不阻塞页面。
    }
  }

  void _edit() {
    _githubCtrl.text = _github;
    _authorCtrl.text = _author;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑项目信息'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _githubCtrl,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'GitHub 仓库地址',
                  hintText: 'https://github.com/<owner>/<repo>',
                ),
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return null; // 留空 = 未配置
                  return AppMeta.isValidUrl(s) ? null : '请填写完整的 http(s) 仓库地址';
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _authorCtrl,
                decoration: const InputDecoration(
                  labelText: '作者 / 组织 / 版权',
                  hintText: '例如：某某（团队）；无 LICENSE 时请一并补齐',
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '留空表示未配置；仅保存在本机，不会上传。也可直接改 '
                'lib/config/app_meta.dart 里的默认常量。',
                style: TextStyle(fontSize: 11.5, height: 1.6, color: AppColors.ink400),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (!(_formKey.currentState?.validate() ?? false)) return;
              final g = _githubCtrl.text.trim();
              final a = _authorCtrl.text.trim();
              setState(() {
                _github = g;
                _author = a;
              });
              Navigator.pop(ctx);
              unawaited(_persist(g, a));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已保存到本机'), duration: Duration(seconds: 1)),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _openGithub() {
    if (!AppMeta.isValidUrl(_github)) return;
    openExternal(_github);
  }

  void _openReleases() => openExternal(AppMeta.releasesUrl);

  void _copyReleases() {
    Clipboard.setData(const ClipboardData(text: AppMeta.releasesUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制下载页地址'), duration: Duration(seconds: 1)),
    );
  }

  void _copyGithub() {
    if (!AppMeta.isValidUrl(_github)) return;
    Clipboard.setData(ClipboardData(text: _github));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制项目地址'), duration: Duration(seconds: 1)),
    );
  }

  Widget _card(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(title, style: const TextStyle(
                fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.ink700)),
          ),
          ...children,
        ]),
      );

  Widget _row(String label, String value, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 96,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.ink400)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(
                fontSize: 12.5, height: 1.5, color: AppColors.ink700)),
          ),
          ?trailing,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final hasGithub = AppMeta.isValidUrl(_github);
    final hasAuthor = _author.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('关于')),
      body: AuroraBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            AnimatedEntrance(
              child: GradientCard(
                radius: AppRadius.hero,
                gradient: AppColors.heroGradient,
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Row(children: [
                  const Icon(Icons.info_outline, color: Colors.white, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text(AppMeta.appName, style: TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text('客户端版本 ${AppMeta.clientVersionLabel} · ${AppMeta.tagline}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 14),

            _card('软件信息', [
              _row('应用名称', AppMeta.appName),
              _row('产品全名', AppMeta.productName),
              _row('客户端版本', AppMeta.clientVersionLabel),
              _row('内容数据版本', '${AppMeta.serverVersion}（构建期导出 assets/offline）'),
              _row('包名', AppMeta.packageName),
              _row('技术栈', AppMeta.stack),
              _row('本地地址', AppMeta.localUrls),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '客户端版本取自 pubspec.yaml；内容数据版本是离线资源的导出版本，两者编号体系不同。',
                  style: TextStyle(fontSize: 11.5, height: 1.6, color: AppColors.ink400),
                ),
              ),
            ]),

            _card('项目地址与作者', [
              _row('项目地址（GitHub）', hasGithub ? _github : '未配置',
                  trailing: hasGithub
                      ? IconButton(
                          tooltip: '复制项目地址',
                          icon: const Icon(Icons.copy_all_outlined, size: 18, color: AppColors.brand),
                          onPressed: _copyGithub,
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        )
                      : null),
              _row('最新版本下载', AppMeta.releasesUrl.replaceFirst('https://', ''),
                  trailing: IconButton(
                    tooltip: '复制下载页地址',
                    icon: const Icon(Icons.copy_all_outlined, size: 18, color: AppColors.brand),
                    onPressed: _copyReleases,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  )),
              _row('作者 / 版权', hasAuthor ? _author : '未声明'),
              _row('软件许可', '${AppMeta.licenseName}（仅覆盖代码与自撰材料）'),
              const SizedBox(height: 8),
              Text(
                '本项目为个人非官方学习工具，与任何政党、政府机关、出版社或研究机构'
                '均无隶属关系。仓库内 ${AppMeta.contentWorkCount} 部原著正文的著作权'
                '不属于本项目，归各作者、译者与出版者；权利状态与异议处理见仓库根目录 '
                '${AppMeta.contentNoticeDoc}。',
                style: const TextStyle(fontSize: 11.5, height: 1.65, color: AppColors.ink500),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: _openReleases,
                  icon: const Icon(Icons.system_update_alt, size: 18),
                  label: const Text('下载最新安卓版'),
                ),
                OutlinedButton.icon(
                  onPressed: hasGithub ? _openGithub : null,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('打开 GitHub'),
                ),
                TextButton.icon(
                  onPressed: _edit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('自定义地址'),
                ),
              ]),
            ]),

            _card('关于本系统', [
              const Text(
                '正统马哲深度学习系统：三条学习路线、逐章精读、章节测验与学情分析。'
                '章节正文随安装包内置，按段落切分、可逐段对照原著；'
                '延伸阅读按经典 / 历史文本 / 民间 / 批判对象分档，'
                '未入正文库的条目只作导读，不冒充原文。',
                style: TextStyle(fontSize: 12.5, height: 1.65, color: AppColors.ink500),
              ),
              const SizedBox(height: 8),
              const Text(
                'Flutter 单机应用 · 无后端 / 无外部 CDN 与字体依赖；'
                '默认离线可用：对话由本机检索式生成，不联网、不需要模型密钥。'
                '如需更强生成能力，可在「功能 → AI 大模型 API 配置」里填入自己的'
                ' API Key（只存本机，不上传），断网或调用失败自动回落本机引擎。',
                style: TextStyle(fontSize: 12.5, height: 1.65, color: AppColors.ink500),
              ),
            ]),

            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showUsageGuide(context),
                  icon: const Icon(Icons.help_outline_rounded, size: 18),
                  label: const Text('查看软件使用说明'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LegalScreen())),
              icon: const Icon(Icons.privacy_tip_outlined, size: 18),
              label: const Text('隐私政策 · 用户协议 · 免责声明'),
            ),
            const SizedBox(height: 8),
            Text(
              AppMeta.operatorConfigured
                  ? '运营者：${AppMeta.operatorName}· ${AppMeta.operatorEmail}'
                  : '运营者信息尚未配置（自用可用，上架应用商店前必须补齐）。',
              style: const TextStyle(fontSize: 11.5, height: 1.6, color: AppColors.ink400),
            ),
            const SizedBox(height: 12),
            const Text(
              '未配置的字段不会指向任何第三方链接或显示虚构署名。',
              style: TextStyle(fontSize: 11.5, color: AppColors.ink400),
            ),
          ],
        ),
      ),
    );
  }
}
