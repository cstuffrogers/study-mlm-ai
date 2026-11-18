// 软件使用说明弹窗 — 首页「引导」按钮点击后弹出。
// 纯 UI，不发网络请求；内容涵盖本系统的主要学习闭环与配置入口。
import 'package:flutter/material.dart';
import '../models/message.dart';
import '../theme/app_theme.dart';

/// 每种模式「什么时候用它」——模式本身（标签 + 会给什么）取自 ChatMode，
/// 保证界面说明与引擎真实产物一致，不在两处各写一遍。
const List<String> _whenUse = [
  '读一段看不懂的原文，先要一个准确的界定和依据',
  '想自己动脑：只要递进的问题，不要现成答案',
  '准备跟人辩论，或要应付别人对这句话的质疑',
  '写文章要找跨著作印证，或把概念和别的书串起来',
  '临考前要能直接默写的答题骨架与得分点',
];

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
                  children: [
                    const _GuideSection(
                      icon: Icons.play_circle_outline,
                      title: '一、开始学习',
                      lines: [
                        '1. 首页先选「学习路线」，再点选「起始章节」。',
                        '2. 底部「深入学习」进入章节导读；有原文时也可点「查看原文」直接读本机正文库。',
                        '3. 学完导读后可点「学完导读，开始章节测试」检验掌握度。',
                      ],
                    ),
                    const _GuideSection(
                      icon: Icons.record_voice_over_outlined,
                      title: '二、深入学习页',
                      lines: [
                        '· 红色顶部卡最左侧的小喇叭：一次性朗读整页导读（背景/概念/正文/要点/思考题/知识点/延伸阅读）。再点一次停止。',
                        '· 右上角书本图标「看原文全文」：进入该章著作的分页原文阅读器。',
                        '·「相关原文」按钮：点开对应原文卡片，可核对著作、位置与正文；界面不再显示内部编码。',
                        '· 「该读哪部分原文」：定位到正文导读段落，并按板块跳到相关原文。',
        '· 右上角「相关原文」卡片里可拖动选中正文，选中即浮出「释义 / 追问 / 辩难 / 关联 / 应试」小面板；关掉卡片时正在朗读的内容会自动停止。',
                      ],
                    ),
                    const _GuideSection(
                      icon: Icons.touch_app_outlined,
                      title: '三、选中文字 → AI 释义',
                      lines: [
                        '· 在导读、原文、原文卡片、溯源卡片里拖动选中一段文字，都只浮出本应用的「释义 / 追问 / 辩难 / 关联 / 应试」小面板，不弹系统自带的「复制 / 全选」菜单，两套浮框不会同时出现。',
        '· 需要复制时点小面板里的「复制」即可。',
                        '· 小面板里的小喇叭可以朗读选中的那段话；把面板收起（点「关闭」/ 发问 / 选中别处 / 退出原文卡片）时，朗读会立即停止。',
                        '· 点任一模式即把选中文字作为锚点送入 AI 对话浮窗；浮窗可拖动、收起、通过底部 AI 按钮重开。',
                        '· 生成中会显示等待状态，失败会显示错误与「重试」。',
                        '· AI 回答不显示任何内部编号；需要核对依据时，点回答下方的「相关原文」按钮即可跳到原著对应位置对照阅读。',
                      ],
                    ),
                    _GuideSection(
                      icon: Icons.fork_right_rounded,
                      title: '四、五种对话模式各给什么　【重点】',
                      lines: <String>[
                        '入口：选中一段文字后浮出的小面板，或对话浮窗输入框左侧的彩色胶囊。点一下即可切换，切换后下一条提问才生效。',
                        '每条回答上方都用文字标出用的是哪种模式（不只靠颜色区分），回答里的引文都带出处。',
                        for (final m in ChatMode.values) '· ${m.label}：${m.desc}',
                        '什么时候用哪个：',
                        for (var i = 0; i < ChatMode.values.length && i < _whenUse.length; i++)
                          '　　${ChatMode.values[i].label} —— ${_whenUse[i]}',
                        '同一句原文换模式会拿到完全不同的产物：模式不是换皮，是换产物。拿不准就先看「释义」，它先给逐字引文和出处，再给界定。',
                        '本机引擎（没配大模型）也照这套产出；配了在线模型则由模型作答，但同样要过立场层。',
                      ],
                    ),
                    const _GuideSection(
                      icon: Icons.swap_horiz_rounded,
                      title: '五、对话浮窗里的「批判性阅读」按钮　【重点】',
                      lines: [
                        '· 位置：AI 对话浮窗顶部标题栏右侧的双向箭头 ⇄ 按钮（红色高亮为「开」，白色为「关」）。',
                        '· 用法：默认关闭；点一下开启后，再发送的问题才会按批判性阅读模式回答，已生成的回答不会变化。开关状态会保留（收起浮窗再打开、切换章节仍在），直到你再点一次关掉或重启应用。',
                        '· 作用：仅当需要涉及西方马克思主义、修正主义等非正统概念时才生效。系统不是把它们当作「另一种视角」中立介绍，而是以「指出其错误」的批判姿态呈现，并用【批判对象·非借鉴】…【/批判对象】标记包住，说明错在哪、与正统原理如何对立；标记外仍只用正统原理解释。',
                        '· 与「辩难」模式的区别：辩难模式是让你练习批判历史上的唯心主义/机械唯物主义；本按钮用于阅读非正统文本时的概念防火墙，二者互不等价。',
                        '· 若回答触发「防偏离拦截」，拦截卡片会提示可切换此模式；开启后点「重试」重新提问即可。不需要时再点一次按钮关掉。',
                      ],
                    ),
                    _GuideSection(
                      icon: Icons.tune_outlined,
                      title: '六、功能中心与大模型 API',
                      lines: [
                        '· 首页就是「选学习路线」：三张路线卡片，点一张进入该路线的章节地图。',
                        '· 首页右上四个图标：功能中心（学习路线 / 学习分析 / 原著浏览 / 对话历史 / 错题本 / LLM 大模型 API 配置 / 本机数据 / 关于）、LLM 大模型 API 配置、学习分析、本使用说明。',
                        '· 「关于」里可查看客户端版本、内容数据版本、项目地址与作者；地址与署名是代码内置的固定值，客户端不提供修改入口（改了不生效，需重新构建）。',
                        '· 「LLM 大模型 API 配置」里填写 API Key / Base URL / 模型名即可启用在线大模型（OpenAI 兼容端点）；可先点「测试连接」。',
                        '· 密钥只存在本机、不上传；保存后下一次提问即生效。不填密钥、断网或调用失败时自动回退本机引擎，回答上方会标出「本机引擎」还是「在线模型」。',
                        '· 推理型模型建议保持「关闭思维链」开启，并把对话超时设为 30 秒以上，否则可能因响应过慢回退本机引擎。',
                        '· 无论哪种引擎，回答都要过本机立场层：偏离表述会被拦下，开启「批判性阅读」后才作为被批判对象呈现。',
                      ],
                    ),
                    const _GuideSection(
                      icon: Icons.chrome_reader_mode_outlined,
                      title: '七、原文阅读器（分页读原著）',
                      lines: [
                        '· 进入方式：章节页「看原文全文」，或任意「相关原文」按钮跳到对应位置。',
                        '· 右上角书本图标 = 「看原文全文」；右上角对话图标 = 打开会话浮窗。对话图标只打开空会话，不会自动替你发问，问什么由你自己说。',
                        '· 右上角小喇叭 = 朗读当前这一页。',
                        '· 右上角耳机图标 = 自动连续发声，弹三个选项：当前页循环播放 / 从当前页播到结束 / 播完再整篇循环。选完自动往下念，念完一页自动翻到下一页；切后台、息屏也继续念，退出原文页才停。连续朗读时底部栏会显示「连续朗读 · 模式」和「停止」。连续朗读中手动翻页 = 把朗读跟到新的一页，不会停。改字号会重新分页，连续朗读会先停下。',
                        '· 翻页即停朗读：未开自动连续发声时，上一页/下一页、左右滑动、跳页、页码输入框跳转，都会先停掉正在朗读的内容，避免听到的和你看到的对不上。同一页里滚动、改字号不会打断朗读。',
                        '· 退出阅读器、切到别的页面、切到后台或息屏，朗读都会停（自动连续发声按你的要求在后台继续，直到退出原文页）。',
                        '· 会话浮窗里每条回答都有小喇叭；收起浮窗时，正在朗读的那条会自动停止。',
                      ],
                    ),
                    _GuideSection(
                      icon: Icons.menu_book_outlined,
                      title: '八、关于原文',
                      lines: [
                        '· 标「有原文」的章节，正文随安装包内置（构建期由 sources/texts 导出），阅读器中的文字均为原文照录。',
                        '· 内容库里没有逐条标注的导读型知识点，只提供「相关原文」入口，其中片段为关键词检索所得、非逐条权威溯源，绝不冒充权威溯源。',
                      ],
                    ),
                    const _GuideSection(
                      icon: Icons.shield_outlined,
                      title: '九、升级与数据保留　【重点】',
                      lines: [
                        '· 安卓版支持应用内更新：只在第一次打开应用时自动查一次新版（从后台切回来不会反复弹），有更新会弹「发现新版本」，点「下载更新」就在后台下载，下载期间可以照常用应用；下完再单独问一句「现在装吗」。也可以随时到「功能中心 → 关于 → 检查更新」手动查，同样走后台下载（关于页能看到进度条）；查不到会明确提示「已是最新版本」。',
                        '· 首次点「立即安装」时，系统可能弹「是否允许安装未知应用」——这是安卓系统对「从应用内装包」的统一要求，不是本应用在索取额外权限。',
                        '· 更新框里有「稍后」和「去网页下载」两个退路；下载进度是真实的，文件不完整不会拿去安装；装不装最后都由你点，不会静默安装。',
                        '· 自动更新只在安卓版提供；桌面版与网页版请在「关于 → 去下载页」下载。',
                        '· 覆盖安装新版本不会清空本机数据。对话记录、学习记录（答题流水与测验）、学情（掌握度与校准）、章节进度、原文笔记/书签/划线、原文阅读进度、大模型 API 设置全部原样保留——前提是安装官方包（包名与签名一致）。',
                        '· 会丢数据的只有三种情况：卸载重装、换手机、在系统设置里「清除应用数据」。这三种请先到「功能中心 → 本机数据 → 复制备份」，把那段 JSON 存一份；新机上再「从剪贴板恢复」。',
                        '· 恢复是合并式的：同名记录以备份为准，本机有而备份里没有的数据不会被删除。API Key 出于安全不进备份，换机恢复后到大模型配置页重填一次即可，其余设置一并回来。',
                        '· 所有数据只存本机（不注册、不上传），卸载应用即一并删除，请自行留底。',
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
            // 标题可能很长（如「五、对话浮窗里的「批判性阅读」按钮　【重点】」），
            // 窄屏 + 字号放大时必须换行，否则整行向右溢出。
            Expanded(
              child: Text(title, style: const TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.ink700)),
            ),
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
