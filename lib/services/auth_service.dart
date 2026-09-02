import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// 用户信息
class AppUser {
  final int id;
  final String username;
  final String nickname;
  final String? avatar;
  final String role;
  final String token;

  AppUser({
    required this.id,
    required this.username,
    required this.nickname,
    this.avatar,
    required this.role,
    required this.token,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as int,
      username: json['username'] as String,
      nickname: json['nickname'] as String? ?? json['username'] as String,
      avatar: json['avatar'] as String?,
      role: json['role'] as String? ?? 'user',
      token: json['token'] as String,
    );
  }
}

/// 认证服务：登录、注册、保存登录态
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const String _keyUser = 'current_user';
  static const String _keyBaseUrl = 'api_base_url';

  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  /// 启动时从本地存储恢复登录态
  Future<bool> restoreLogin() async {
    final prefs = await SharedPreferences.getInstance();

    // 先恢复服务器地址
    final savedUrl = prefs.getString(_keyBaseUrl);
    if (savedUrl != null && savedUrl.isNotEmpty) {
      ApiService.instance.setBaseUrl(savedUrl);
    }

    final str = prefs.getString(_keyUser);
    if (str == null) return false;
    try {
      final json = jsonDecode(str) as Map<String, dynamic>;
      _currentUser = AppUser.fromJson(json);
      // 同步到 ApiService（带 token）
      ApiService.instance.setAuthToken(_currentUser!.token);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 保存服务器地址（登录页修改后调用）
  Future<void> saveBaseUrl(String url) async {
    ApiService.instance.setBaseUrl(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBaseUrl, ApiService.instance.baseUrl);
  }

  /// 读取已保存的服务器地址，没有则返回当前 baseUrl
  Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBaseUrl) ?? ApiService.instance.baseUrl;
  }

  /// 登录
  Future<AppUser> login(String username, String password) async {
    final response = await ApiService.instance.dio.post(
      '/api/login',
      data: {'username': username, 'password': password},
    );
    final user = AppUser.fromJson(response.data as Map<String, dynamic>);
    _currentUser = user;
    _persist(user);
    ApiService.instance.setAuthToken(user.token);
    return user;
  }

  /// 注册
  Future<AppUser> register(String username, String password, String nickname) async {
    final response = await ApiService.instance.dio.post(
      '/api/register',
      data: {'username': username, 'password': password, 'nickname': nickname},
    );
    final user = AppUser.fromJson(response.data as Map<String, dynamic>);
    _currentUser = user;
    _persist(user);
    ApiService.instance.setAuthToken(user.token);
    return user;
  }

  /// 登出
  Future<void> logout() async {
    try {
      await ApiService.instance.dio.post('/api/logout');
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUser);
    _currentUser = null;
    ApiService.instance.setAuthToken(null);
  }

  Future<void> _persist(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUser, jsonEncode({
      'id': user.id,
      'username': user.username,
      'nickname': user.nickname,
      'avatar': user.avatar,
      'role': user.role,
      'token': user.token,
    }));
  }
}
