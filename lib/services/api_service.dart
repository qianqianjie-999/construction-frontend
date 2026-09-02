import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../models/project.dart';
import '../models/construction_log.dart';

class ApiService {
  // 默认 API 基础 URL
  // 优先级：运行时 setBaseUrl() > 编译期 --dart-define=API_BASE_URL > 默认 localhost
  static const String _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://123.57.86.80:9304',
  );

  final Dio _dio;

  // 运行时地址（登录页可修改）
  String _baseUrl = _defaultBaseUrl;

  // 单例模式
  static final ApiService _instance = ApiService._internal();

  factory ApiService() {
    return _instance;
  }

  ApiService._internal() : _dio = Dio() {
    // 强制用 IO adapter，并忽略自签名 SSL 证书
    final ioAdapter = IOHttpClientAdapter();
    ioAdapter.createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      client.connectionTimeout = const Duration(seconds: 30);
      return client;
    };
    _dio.httpClientAdapter = ioAdapter;

    _dio.options.baseUrl = _baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);

    // 添加日志拦截器
    _dio.interceptors.add(LogInterceptor(
      request: true,
      requestBody: true,
      responseBody: true,
      error: true,
      logPrint: kDebugMode ? print : (obj) {},
    ));

    // 添加错误处理拦截器
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (error, handler) {
        if (error.response?.statusCode == 401) {
          // TODO: 处理未授权情况（如跳转到登录页）
        }
        return handler.next(error);
      },
    ));
  }

  Future<List<Project>> getProjects() async {
    try {
      final response = await _dio.get('/api/projects');
      return (response.data as List)
          .map((e) => Project.fromJson(e))
          .toList();
    } catch (e) {
      debugPrint('Error fetching projects: $e');
      rethrow;
    }
  }

  Future<List<ConstructionLog>> getLogsByProject(int projectId) async {
    try {
      final response = await _dio.get('/api/logs', queryParameters: {'project_id': projectId});
      return (response.data as List)
          .map((e) => ConstructionLog.fromJson(e))
          .toList();
    } catch (e) {
      debugPrint('Error fetching logs: $e');
      rethrow;
    }
  }

  Future<void> createLog(ConstructionLog log, List<dynamic> photos, List<dynamic> certificates) async {
    try {
      final formData = FormData();

      // 添加日志的文本数据
      formData.fields.add(MapEntry('project_id', log.projectId.toString()));
      formData.fields.add(MapEntry('date', log.dateStr));
      formData.fields.add(MapEntry('weather', log.weather));
      formData.fields.add(MapEntry('temperature', log.temperature));
      formData.fields.add(MapEntry('wind_force', log.windForce));
      formData.fields.add(MapEntry('wind_direction', log.windDirection));
      formData.fields.add(MapEntry('construction_part', log.constructionPart));
      formData.fields.add(MapEntry('construction_content', log.constructionContent));
      formData.fields.add(MapEntry('progress', log.progress));
      formData.fields.add(MapEntry('construction_record', log.constructionRecord));
      formData.fields.add(MapEntry('technical_safety_record', log.technicalSafetyRecord));
      formData.fields.add(MapEntry('material_record', log.materialRecord));
      formData.fields.add(MapEntry('project_manager', log.projectManager));
      formData.fields.add(MapEntry('recorder', log.recorder));

      // 添加现场照片（image_picker 新版全平台都返回 XFile）
      for (var i = 0; i < photos.length; i++) {
        final xFile = photos[i] as XFile;
        final bytes = await xFile.readAsBytes();
        formData.files.add(MapEntry(
          'photos',
          MultipartFile.fromBytes(bytes, filename: xFile.name),
        ));
      }

      // 添加合格证照片
      for (var i = 0; i < certificates.length; i++) {
        final xFile = certificates[i] as XFile;
        final bytes = await xFile.readAsBytes();
        formData.files.add(MapEntry(
          'certificates',
          MultipartFile.fromBytes(bytes, filename: xFile.name),
        ));
      }

      await _dio.post('/api/logs', data: formData);
    } catch (e) {
      debugPrint('Error uploading log: $e');
      rethrow;
    }
  }

  // 获取单例实例
  static ApiService get instance => _instance;

  /// 暴露 dio 给其他服务使用
  Dio get dio => _dio;

  /// 当前 baseUrl（运行时地址）
  String get baseUrl => _baseUrl;

  /// 运行时设置后端服务器地址（登录页调用），自动规范格式并同步到 dio
  void setBaseUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) return;
    // 去掉末尾多余的斜杠
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    _baseUrl = u;
    _dio.options.baseUrl = u;
  }

  /// 设置/清除认证 token
  void setAuthToken(String? token) {
    if (token == null) {
      _dio.options.headers.remove('Authorization');
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  // 删除项目
  Future<void> deleteProject(int projectId) async {
    try {
      await _dio.delete('/api/projects/$projectId');
    } catch (e) {
      debugPrint('Error deleting project: $e');
      rethrow;
    }
  }

  // 导出施工日志
  Future<Uint8List> exportLogs(int projectId, String format) async {
    try {
      final response = await _dio.get(
        '/api/export/logs',
        queryParameters: {
          'project_id': projectId,
          'format': format, // 'pdf' 或 'excel'
        },
        options: Options(
          responseType: ResponseType.bytes,
        ),
      );
      return response.data;
    } catch (e) {
      debugPrint('Error exporting logs: $e');
      rethrow;
    }
  }

  // 移除 dispose 方法，单例模式下不需要
}
