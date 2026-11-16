// 软件使用说明弹窗 — 首页「引导」按钮点击后弹出。
// 纯 UI，不发网络请求；内容涵盖本系统的主要学习闭环与配置入口。
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 弹出《软件使用说明》。可在任意有 BuildContext 的页面调用。
Future<void> showUsageGuide(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.hero)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(gradient: AppColors.heroGradient),
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
              child: Row(children: [
                const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 24),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('软件使用说明',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _GuideSection(
                      icon: Icons.play_circle_outline,
                      title: '一、开始学习',
                      lines: [
                        '1. 首页先选「学习路线」，再点选「起始章节」。',
                        '2. 底部「深入学习」进入章节导读；有原文时也可点「查看原文」直接读本机正文库。',
                        '3. 学完导读后可点「学完导读，开始章节测试」检验掌握度。',
                      ],
                    ),
                    _GuideSection(
                      icon: Icons.record_voice_over_outlined,
                      title: '二、深入学习页',
                      lines: [
                        '· 红色顶部卡最左侧的小喇叭：一次性朗读整页导读（背景/概念/正文/要点/思考题/知识点/延伸阅读）。再点一次停止。',
                        '· 右上角书本图标「看原文全文」：进入该章著作的分页原文阅读器。',
                        '·「相关原文」按钮：点开对应原文卡片，可核对著作、位置与正文；界面不再显示内部编码。',
                        '· 「该读哪部分原文」：定位到正文导读段落，并按板块跳到相关原文。',
                      ],
                    ),
                    _GuideSection(
                      icon: Icons.touch_app_outlined,
                      title: '三、选中文字 → AI 释义',
                      lines: [
                        '· 在导读或原文里拖动选中一段文字，会浮出「释义 / 追问 / 辩难 / 关联 / 应试」小面板。',
                        '· 点任一模式即把选中文字作为锚点送入 AI 对话浮窗；浮窗可拖动、收起、通过底部 AI 按钮重开。',
                        '· 生成中会显示等待状态，失败会显示错误与「重试」。',
                        '· AI 回答不显示任何内部编号；需要核对依据时，点回答下方的「相关原文」按钮即可跳到原著对应位置对照阅读。',
                      ],
                    ),
                    _GuideSection(
                      icon: Icons.swap_horiz_rounded,
                      title: '四、对话浮窗里的「批判性阅读」按钮　【重点】',
                      lines: [
                        '· 位置：AI 对话浮窗顶部标题栏、模式下拉框右侧的双向箭头 ⇄ 按钮（红色高亮为「开」，白色为「关」）。',
                        '· 用法：默认关闭；点一下开启后，再发送的问题才会按批判性阅读模式回答，已生成的回答不会变化。开关状态会保留（收起浮窗再打开、切换章节仍在），直到你再点一次关掉或重启应用。',
                        '· 作用：仅当需要涉及西方马克思主义、修正主义等非正统概念时才生效。系统不是把它们当作「另一种视角」中立介绍，而是以「指出其错误」的批判姿态呈现，并用【批判对象·非借鉴】…【/批判对象】标记包住，说明错在哪、与正统原理如何对立；标记外仍只用正统原理解释。',
                        '· 与「辩难」模式的区别：辩难模式是让你练习批判历史上的唯心主义/机械唯物主义；本按钮用于阅读非正统文本时的概念防火墙，二者互不等价。',
                        '· 若回答触发「防偏离拦截」，拦截卡片会提示可切换此模式；开启后点「重试」重新提问即可。不需要时再点一次按钮关掉。',
                      ],
                    ),
                    _GuideSection(
                      icon: Icons.tune_outlined,
                      title: '五、功能中心与大模型 API',
                      lines: [
                        '· 首页右上四个图标即可进入：功能中心（学习路线 / 学习分析 / 原著浏览 / 对话历史 / 错题本 / LLM 大模型 API 配置 / 关于）、学习路线、学习分析、本使用说明。',
                        '· 「关于」里可查看客户端版本、内容数据版本、项目地址与作者，并补填尚未配置的仓库链接或署名。',
                        '· 「LLM 大模型 API 配置」里填写 API Key / Base URL / 模型名即可启用在线大模型（OpenAI 兼容端点）；可先点「测试连接」。',
                        '· 密钥只存在本机、不上传；保存后下一次提问即生效。不填密钥、断网或调用失败时自动回退本机引擎，回答上方会标出「本机引擎」还是「在线模型」。',
                        '· 推理型模型建议保持「关闭思维链」开启，并把对话超时设为 30 秒以上，否则可能因响应过慢回退本机引擎。',
                        '· 无论哪种引擎，回答都要过本机立场层：偏离表述会被拦下，开启「批判性阅读」后才作为被批判对象呈现。',
                      ],
                    ),
                    _GuideSection(
                      icon: Icons.menu_book_outlined,
                      title: '六、关于原文',
                      lines: [
                        '· 标「有原文」的章节，正文随安装包内置（构建期由 sources/texts 导出），阅读器中的文字均为原文照录。',
                        '· 内容库里没有逐条标注的导读型知识点，只提供「相关原文」入口，其中片段为关键词检索所得、非逐条权威溯源，绝不冒充权威溯源。',
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('我知道了', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _GuideSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> lines;
  const _GuideSection({required this.icon, required this.title, required this.lines});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 17, color: AppColors.brand),
            const SizedBox(width: 7),
            Text(title, style: const TextStyle(
                fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.ink700)),
          ]),
          const SizedBox(height: 6),
          ...lines.map((l) => Padding(
                padding: const EdgeInsets.only(left: 24, bottom: 4),
                child: Text(l, style: const TextStyle(
                    fontSize: 12.5, height: 1.65, color: AppColors.ink500)),
              )),
        ],
      ),
    );
  }
}
