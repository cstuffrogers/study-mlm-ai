// 「法律与隐私」页：隐私政策 + 用户协议 + 免责声明 + 内容来源与版权说明。
//
// 为什么要有这一页（合规必需）：
// · 应用商店审核把「可打开的隐私政策」当硬性项，缺了一律退回；
// · 本应用几乎不收集个人信息，但「不收集」也需要如实说明清楚，不能什么都不写；
// · 内容库含 229 部原著，需要如实交代来源与仍在保护期内的部分，不做模糊表述。
//
// 口径纪律（与本项目其他「如实展示」页面一致）：
// · **不编造**运营者名称、邮箱、备案号。未配置就显示「未配置」并给出待办横幅，
//   由运营者改 lib/config/app_meta.dart 填入真实值。
// · 版权到期日按《著作权法》一般作品口径（作者终生 + 死后 50 年，截止于第 50 年
//   12 月 31 日）如实计算并写明；**具体法律结论请咨询专业人士**，页面不代替法律意见。
import 'package:flutter/material.dart';

import '../config/app_meta.dart';
import '../theme/app_theme.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('法律与隐私')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          if (!AppMeta.operatorConfigured) _todoBanner(),
          _card('一、免责声明', [
            _p('本应用是**个人学习用途的非官方项目**，与人民出版社、中央编译局、'
                '各级党校及任何政党、政府机构均无隶属、授权或合作关系。'),
            _p('应用内全部内容仅用于马克思主义经典著作的阅读与学习研究，'
                '不构成政治宣传、学术定论或任何形式的权威解释。'),
            _p('应用内所有导读、注释、测验题与 AI 回答均为项目自撰的辅助材料，'
                '**不是原著，也不代表官方观点**；引用与理解请以正式出版物为准。'),
            _p('使用者应自行判断内容的适用性。因使用本应用产生的任何后果，'
                '由使用者自行承担。'),
          ]),
          _card('二、隐私政策', [
            _h('我们收集什么'),
            _p('**不收集任何个人信息**。本应用没有账号体系、没有注册登录、'
                '没有埋点统计、没有广告 SDK、没有崩溃上报 SDK，也不向任何服务器'
                '回传使用行为。'),
            _h('哪些数据存在你的设备上'),
            _bullet('学习记录：章节进度、掌握度、答题记录、错题本、对话历史'),
            _bullet('偏好设置：字号、主题、朗读音色等'),
            _bullet('AI 大模型配置：你自行填写的 API Key、接口地址、模型名'),
            _p('以上数据全部保存在本机（SharedPreferences / 应用私有目录），'
                '**不会上传**，卸载应用即随之删除。'),
            _h('唯一可能的外发请求'),
            _p('只有当你**自己**在「AI 大模型 API 配置」里填好 API Key、接口地址、'
                '模型名三项并主动提问时，应用才会把你输入的**问题文本**、'
                '命中的原著片段与概念卡发送到你指定的那个接口。'
                '不填、断网或调用失败时，全部回答由本机引擎生成，不产生任何网络请求。'),
            _p('请求中**不包含**设备标识、手机号、位置、通讯录、账号信息或历史学习记录。'
                '该第三方接口的隐私处理由你选择的模型提供方负责。'),
            _h('权限'),
            _p('本应用只申请网络权限（用于上述可选的大模型调用）。'
                '不申请相机、麦克风、通讯录、位置、存储、后台自启等任何权限。'),
            _h('如何删除数据'),
            _p('卸载应用即删除全部本地数据。也可在应用内「学习分析」等页面重置进度，'
                '或在系统设置中清除本应用数据。'),
            _h('未成年人'),
            _p('本应用不面向未成年人单独提供服务，也不收集任何年龄信息。'),
          ]),
          _card('三、用户协议', [
            _bullet('本应用免费提供，供个人学习、教学与研究使用。'),
            _bullet('不得将本应用或其中的内容用于商业销售、付费分发、'
                '二次打包上架，或以本应用名义对外提供收费服务。'),
            _bullet('不得移除、遮挡应用内的来源与版权说明。'),
            _bullet('如需在公开出版物、课程或产品中引用本应用的导读与题目，'
                '请自行核对原著并注明出处。'),
          ]),
          _card('四、内容来源与版权说明', [
            _p('本应用内置 ${AppMeta.contentWorkCount} 部中文原著正文，'
                '均照录自可溯源的中文版本，**不改写、不伪造、不替代原文**；'
                '版本说明行、译注与按语一并保留。'),
            _p('书目里没有正文的条目只提供导读，界面上明确标注，'
                '**绝不冒充原文**；标注为「批判对象」的条目只作批判性引用，'
                '不进入正面学习路径。'),
            _h('关于著作权保护期'),
            _p('按《中华人民共和国著作权法》一般作品的保护期口径'
                '（作者终生加死亡后五十年，截止于第五十年的 12 月 31 日），'
                '内置书目的作者绝大多数已过保护期。'),
            _p('**需要特别提示的两项**：毛泽东（1976 年 9 月逝世）与'
                '周恩来（1976 年 1 月逝世）的著作，按同一口径的保护期'
                '**至 2026 年 12 月 31 日届满**。本应用收录的这两位作者的'
                '${AppMeta.copyrightPendingCount} 部作品，在 2026 年 12 月 31 日之前'
                '仍处于著作权保护期内。'),
            _p('此外，特定译本的**译者权利**、特定版本的**版式设计权利**与'
                '出版社的**专有出版权**是独立于原作者著作权的另一层权利，'
                '不因原作者保护期届满而消失，需逐项核对。'),
            _p('**上述为事实说明，不构成法律意见。**'
                '公开分发前请就具体书目咨询专业人士。'),
          ]),
          _card('五、AI 生成内容提示', [
            _p('应用内标注「本机引擎」或「在线模型」的回答**均为 AI 生成内容**，'
                '不是原著原文，也不是人工审定的结论，可能不准确。'
                '正式引用请回到原文核对。'),
            _p('涉及原著内容时，回答下方提供「相关原文」入口，'
                '可直接跳到对应段落逐字比对。'),
            _p('模型可能产生错误或虚构内容（俗称「幻觉」），'
                '请勿把 AI 回答当作原著引文使用。'),
          ]),
          _card('六、运营者与联系方式', [
            _row('运营者', AppMeta.operatorName.isEmpty ? '未配置' : AppMeta.operatorName),
            _row('联系邮箱', AppMeta.operatorEmail.isEmpty ? '未配置' : AppMeta.operatorEmail),
            _row('APP 备案号', AppMeta.appFilingNo.isEmpty ? '未配置' : AppMeta.appFilingNo),
            _row('本页版本', AppMeta.contentNoticeVersion),
            const SizedBox(height: 8),
            Text(
              AppMeta.operatorConfigured
                  ? '如对本页内容有异议（含版权问题），请通过上述邮箱联系。'
                  : '运营者信息尚未填写：请在 lib/config/app_meta.dart 里补齐 '
                      'operatorName / operatorEmail / appFilingNo 后再发布。',
              style: const TextStyle(fontSize: 11.5, height: 1.65, color: AppColors.ink500),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _todoBanner() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.goldSoft,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.gold),
        ),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.report_problem_outlined, size: 18, color: AppColors.warning),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              // 注意：这里是普通 Text，不经过 _Rich，所以不要写 **加粗** 标记
              '运营者信息未配置：本页可用于自用与内部测试，但不能直接用于应用商店上架。'
              '发布前请在 lib/config/app_meta.dart 填入 operatorName / operatorEmail / '
              'appFilingNo（APP 备案号）。',
              style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.ink700),
            ),
          ),
        ]),
      );

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
            child: Text(title,
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.ink700)),
          ),
          ...children,
        ]),
      );

  Widget _h(String t) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink700)),
      );

  Widget _p(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _Rich(t),
      );

  Widget _bullet(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 5, left: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('· ', style: TextStyle(fontSize: 12.5, color: AppColors.ink400)),
          Expanded(child: _Rich(t)),
        ]),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 84,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.ink400)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.ink700)),
          ),
        ]),
      );
}

/// 极简粗体标记：`**xxx**` 渲染为加粗。避免为几条法务文案额外引依赖。
class _Rich extends StatelessWidget {
  final String text;
  const _Rich(this.text);

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(fontSize: 12.5, height: 1.7, color: AppColors.ink500);
    final parts = text.split('**');
    if (parts.length == 1) return Text(text, style: base);
    return RichText(
      text: TextSpan(
        style: base,
        children: [
          for (var i = 0; i < parts.length; i++)
            TextSpan(
              text: parts[i],
              style: i.isOdd
                  ? const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink700)
                  : null,
            ),
        ],
      ),
    );
  }
}
