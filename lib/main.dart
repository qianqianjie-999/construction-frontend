import 'package:flutter/material.dart';
import 'package:construction_app/screens/login_screen.dart';
import 'package:construction_app/screens/project_list_screen.dart';
import 'package:construction_app/screens/log_form_screen.dart';
import 'package:construction_app/screens/project_detail_screen.dart';
import 'package:construction_app/services/auth_service.dart';
import 'package:construction_app/models/project.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  initializeDateFormatting('zh_CN', null).then((_) {
    runApp(const MyApp());
  });
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
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00d4ff),
          brightness: Brightness.dark,
          primary: const Color(0xFF00d4ff),
          primaryContainer: const Color(0xFF0a0f1a),
          secondary: const Color(0xFF10b981),
          background: const Color(0xFF0a0f1a),
          surface: const Color(0xFF1a2332),
          surfaceVariant: const Color(0xFF111827),
          onPrimary: const Color(0xFF0a0f1a),
          onSurface: const Color(0xFFf1f5f9),
          onSurfaceVariant: const Color(0xFF94a3b8),
          outline: const Color(0xFF2d3a4f),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Color(0xFF1a2332),
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: const Color(0xFF1a2332),
          surfaceTintColor: Colors.transparent,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          elevation: 4,
          backgroundColor: const Color(0xFF00d4ff),
          foregroundColor: const Color(0xFF0a0f1a),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF111827),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF2d3a4f)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF00d4ff)),
          ),
          hintStyle: const TextStyle(color: Color(0xFF64748b)),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF00d4ff),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00d4ff),
            foregroundColor: const Color(0xFF0a0f1a),
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          ),
        ),
      ),
      home: _initialized
          ? (_isLoggedIn ? const ProjectListScreen() : const LoginScreen())
          : const Scaffold(
              backgroundColor: Color(0xFF0a0f1a),
              body: Center(
                child: CircularProgressIndicator(color: Color(0xFF00d4ff)),
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
}
