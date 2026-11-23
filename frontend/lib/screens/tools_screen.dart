// 功能菜单页 — 汇聚全站入口（学习分析 / 原著浏览 / 对话历史 / 错题本 / 大模型配置 / 语音包设置 / 本机数据 / 关于 / 法律与隐私）
//
// 「学习路线」入口已删（D143）：首页本身就是选学习路线页，这里再放一份是重复入口；
// 要换路线直接返回首页即可。
import 'package:flutter/material.dart';
import '../widgets/anim.dart';
import '../theme/app_theme.dart';
import 'analytics_dashboard.dart';
import 'source_browser_screen.dart';
import 'dialogue_history_screen.dart';
import 'test_history_screen.dart';
import 'data_backup_screen.dart';
import 'llm_config_screen.dart';
import 'tts_settings_screen.dart';
import 'about_screen.dart';
import 'legal_screen.dart';
import 'badge_screen.dart';

class ToolsScreen extends StatelessWidget {
  final String routeId;
  const ToolsScreen({super.key, this.routeId = 'route_A'});

  @override
  Widget build(BuildContext context) {
    final items = <_ToolItem>[
      _ToolItem('学习分析', '健康度 · 校准 · 错因', Icons.insights, AppColors.ink,
          (_) => AnalyticsDashboardScreen(routeId: routeId)),
      _ToolItem('原著浏览', '原著全文 · 逐段对照', Icons.menu_book, AppColors.brand,
          (_) => const SourceBrowserScreen()),
      _ToolItem('对话历史', '会话回看 · 防偏离标记', Icons.forum_outlined, AppColors.success,
          (_) => const DialogueHistoryScreen()),
      _ToolItem('错题本', '测试历史 · 逐题回顾', Icons.fact_check_outlined, AppColors.warning,
          (_) => TestHistoryScreen(routeId: routeId)),
      _ToolItem('我的勋章', '成就徽章 · 达成条件 · 进度追踪',
          Icons.emoji_events_rounded, AppColors.gold,
          (_) => BadgeScreen(routeId: routeId)),
      _ToolItem('LLM 大模型 API 配置', 'API Key · 端点 · 模型 · 立即生效',
          Icons.smart_toy_outlined, AppColors.brandDeep,
          (_) => const LlmConfigScreen()),
      _ToolItem('语音包设置', '中文语音包 · 音调语速风格 · 试听',
          Icons.record_voice_over_outlined, AppColors.success,
          (_) => const TtsSettingsScreen()),
      _ToolItem('本机数据', '升级不丢 · 备份恢复 · 数据体检',
          Icons.backup_outlined, AppColors.info,
          (_) => const DataBackupScreen()),
      _ToolItem('关于', '软件版本 · 项目地址 · 作者 · 使用说明',
          Icons.info_outline, AppColors.gold,
          (_) => const AboutScreen()),
      _ToolItem('法律与隐私', '隐私政策 · 用户协议 · 免责声明 · 内容版权',
          Icons.privacy_tip_outlined, AppColors.info,
          (_) => const LegalScreen()),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFFBF7F5),
      appBar: AppBar(title: const Text('功能')),
      body: AuroraBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          children: [
            AnimatedEntrance(
              child: GradientCard(
                radius: AppRadius.hero,
                gradient: AppColors.heroGradient,
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Row(children: [
                  const Icon(Icons.grid_view_rounded, color: Colors.white, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                      Text('功能中心', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                      SizedBox(height: 3),
                      Text('精读 · 测验 · 学情 · 复习 · 溯源 · 配置', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            ...items.map((it) => _toolTile(context, it)),
          ],
        ),
      ),
    );
  }

  Widget _toolTile(BuildContext context, _ToolItem it) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: it.builder)),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: it.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(it.icon, color: it.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(it.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppColors.ink700)),
                  const SizedBox(height: 3),
                  Text(it.subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.ink400)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: AppColors.ink400),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ToolItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final WidgetBuilder builder;
  _ToolItem(this.title, this.subtitle, this.icon, this.color, this.builder);
}
