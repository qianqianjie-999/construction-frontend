import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:construction_app/screens/login_screen.dart';
import 'package:construction_app/screens/project_list_screen.dart';
import 'package:construction_app/screens/log_form_screen.dart';
import 'package:construction_app/screens/project_detail_screen.dart';
import 'package:construction_app/services/auth_service.dart';
import 'package:construction_app/models/project.dart';
import 'package:intl/date_symbol_data_local.dart';

// ===== 全局颜色常量（一处改，处处变）=====
class AppColors {
  static const background = Color(0xFF0B1220);
  static const surface = Color(0xFF151E2E);
  static const surfaceAlt = Color(0xFF1C2738);
  static const card = Color(0xFF1A2436);
  static const inputFill = Color(0xFF0F1A2A);
  static const border = Color(0xFF263348);
  static const primary = Color(0xFF00D4FF);
  static const primaryDark = Color(0xFF0099CC);
  static const accent = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const text = Color(0xFFF1F5F9);
  static const textSub = Color(0xFF94A3B8);
  static const textMuted = Color(0xFF64748B);
}

void main() {
  HttpOverrides.global = _MyHttpOverrides();
  // 设置状态栏颜色（沉浸式）
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  initializeDateFormatting('zh_CN', null).then((_) {
    runApp(const MyApp());
  });
}

class _MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _initialized = false;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ok = await AuthService().restoreLogin();
    if (!mounted) return;
    setState(() {
      _initialized = true;
      _isLoggedIn = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '工程现场管理',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: _initialized
          ? (_isLoggedIn ? const ProjectListScreen() : const LoginScreen())
          : const Scaffold(
              backgroundColor: AppColors.background,
              body: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
      routes: {
        '/login': (_) => const LoginScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/log_form') {
          final project = settings.arguments as Project;
          return MaterialPageRoute(
            builder: (_) => LogFormScreen(project: project),
          );
        } else if (settings.name == '/project_detail') {
          final project = settings.arguments as Project;
          return MaterialPageRoute(
            builder: (_) => ProjectDetailScreen(project: project),
          );
        }
        return null;
      },
    );
  }

  ThemeData _buildTheme() {
    final cs = const ColorScheme.dark(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.card,
      background: AppColors.background,
      onPrimary: AppColors.background,
      onSurface: AppColors.text,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,

      // ===== AppBar =====
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.text,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
          letterSpacing: 0.3,
        ),
        iconTheme: IconThemeData(color: AppColors.primary, size: 22),
        actionsIconTheme: IconThemeData(color: AppColors.primary, size: 22),
      ),

      // ===== 卡片 =====
      cardTheme: CardTheme(
        elevation: 0,
        color: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),

      // ===== 输入框 =====
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        isDense: true,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        labelStyle: const TextStyle(color: AppColors.textSub),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.danger, width: 2),
        ),
      ),

      // ===== ElevatedButton =====
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.background,
          elevation: 0,
          shadowColor: AppColors.primary.withOpacity(0.35),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.5),
        ),
      ),

      // ===== TextButton =====
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),

      // ===== OutlinedButton =====
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),

      // ===== FAB =====
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.background,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            bottomLeft: Radius.circular(20),
          ),
        ),
      ),

      // ===== SnackBar =====
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surface,
        contentTextStyle: const TextStyle(color: AppColors.text),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      // ===== Dialog =====
      dialogTheme: DialogTheme(
        backgroundColor: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text),
        contentTextStyle: const TextStyle(color: AppColors.textSub, fontSize: 14),
      ),

      // ===== BottomSheet =====
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
      ),

      // ===== 文字主题 =====
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text),
        titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text),
        bodyLarge: TextStyle(fontSize: 16, color: AppColors.text),
        bodyMedium: TextStyle(fontSize: 14, color: AppColors.text),
        bodySmall: TextStyle(fontSize: 13, color: AppColors.textSub),
        labelMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary),
      ),

      // ===== Divider =====
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
