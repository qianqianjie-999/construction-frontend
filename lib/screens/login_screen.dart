import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import 'project_list_screen.dart';

/// 登录页面
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadServer();
  }

  Future<void> _loadServer() async {
    final saved = await AuthService().getBaseUrl();
    if (mounted) {
      _serverController.text = saved;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 先应用服务器地址，再登录
      await AuthService().saveBaseUrl(_serverController.text.trim());
      await AuthService().login(
        _usernameController.text.trim(),
        _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ProjectListScreen()),
      );
    } catch (e) {
      setState(() {
        _error = '登录失败：请检查服务器地址、用户名或密码';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0f1a),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.engineering, size: 80, color: Color(0xFF00d4ff)),
                const SizedBox(height: 16),
                const Text(
                  '施工日志管理',
                  style: TextStyle(
                    color: Color(0xFFf1f5f9),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '请登录以继续',
                  style: TextStyle(color: Color(0xFF94a3b8), fontSize: 14),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _serverController,
                  decoration: _inputDecoration('服务器地址', icon: Icons.dns_outlined),
                  keyboardType: TextInputType.url,
                  style: const TextStyle(color: Color(0xFFf1f5f9)),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return '请输入服务器地址';
                    final uri = Uri.tryParse(s);
                    if (uri == null || !(uri.hasScheme && uri.host.isNotEmpty)) {
                      return '地址格式不正确，如 http://192.168.1.100:5000';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _usernameController,
                  decoration: _inputDecoration('用户名', icon: Icons.person_outline),
                  style: const TextStyle(color: Color(0xFFf1f5f9)),
                  validator: (v) => (v == null || v.trim().isEmpty) ? '请输入用户名' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: _inputDecoration('密码', icon: Icons.lock_outline),
                  style: const TextStyle(color: Color(0xFFf1f5f9)),
                  validator: (v) => (v == null || v.isEmpty) ? '请输入密码' : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00d4ff),
                      foregroundColor: const Color(0xFF0a0f1a),
                    ),
                    child: _loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('登录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1a2332),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF00d4ff).withOpacity(0.3)),
                  ),
                  child: const Column(
                    children: [
                      Text(
                        '默认管理员：admin / admin123',
                        style: TextStyle(color: Color(0xFF94a3b8), fontSize: 12),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '账号由管理员在后台分配',
                        style: TextStyle(color: Color(0xFF64748b), fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon != null ? Icon(icon, color: const Color(0xFF64748b)) : null,
      labelStyle: const TextStyle(color: Color(0xFF94a3b8)),
      filled: true,
      fillColor: const Color(0xFF1a2332),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF334155)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF00d4ff)),
      ),
    );
  }
}
