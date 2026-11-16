// 账号页 — 注册 / 登录（可选接入；失败不阻断，仍可用 demo_user 演示模式）
import 'package:flutter/material.dart';
import '../services/content_service_api.dart';
import '../widgets/anim.dart';
import '../theme/app_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _pwd = TextEditingController();
  final _nick = TextEditingController();
  bool _isLogin = true;
  bool _busy = false;
  String? _msg;
  bool _ok = false;

  @override
  void dispose() {
    _email.dispose();
    _pwd.dispose();
    _nick.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pwd = _pwd.text;
    if (email.isEmpty || pwd.isEmpty) {
      setState(() { _msg = '请填写邮箱与密码'; _ok = false; });
      return;
    }
    setState(() { _busy = true; _msg = null; });
    try {
      final j = _isLogin
          ? await AuthApi().login(email, pwd)
          : await AuthApi().register(email, pwd, nickname: _nick.text.trim());
      setState(() {
        _ok = true;
        _msg = _isLogin
            ? '登录成功，欢迎 ${j['nickname'] ?? j['email'] ?? email}'
            : '注册成功，已创建账号 ${j['email'] ?? email}';
      });
    } catch (e) {
      setState(() { _ok = false; _msg = _isLogin ? '登录失败：$e' : '注册失败：$e'; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF7F5),
      appBar: AppBar(title: const Text('我的账号')),
      body: AuroraBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            GradientCard(
              radius: AppRadius.hero,
              gradient: AppColors.heroGradient,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.verified_user_outlined, color: Colors.white, size: 28),
                const SizedBox(height: 10),
                Text(_isLogin ? '登录你的学习账号' : '注册新账号',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('账号用于跨设备同步学情；不登录也可用 demo 演示模式。',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12, height: 1.5)),
              ]),
            ),
            const SizedBox(height: 20),
            _field(_email, '邮箱', Icons.mail_outline, keyboard: TextInputType.emailAddress),
            const SizedBox(height: 12),
            _field(_pwd, '密码', Icons.lock_outline, obscure: true),
            if (!_isLogin) ...[
              const SizedBox(height: 12),
              _field(_nick, '昵称（可选）', Icons.badge_outlined),
            ],
            if (_msg != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(_msg!,
                    style: TextStyle(fontSize: 12.5, height: 1.5,
                        color: _ok ? AppColors.success : AppColors.danger)),
              ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_isLogin ? '登录' : '注册', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: _busy ? null : () => setState(() { _isLogin = !_isLogin; _msg = null; }),
                child: Text(_isLogin ? '没有账号？去注册' : '已有账号？去登录',
                    style: const TextStyle(color: AppColors.brand)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon,
          {bool obscure = false, TextInputType? keyboard}) =>
      TextField(
        controller: c,
        obscureText: obscure,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.line),
          ),
        ),
      );
}
