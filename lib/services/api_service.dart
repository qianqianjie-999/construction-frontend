import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../models/project.dart';
import '../models/construction_log.dart';

/// 网络重试事件（用于在 UI 上给用户可见反馈）
class RetryEvent {
  final String path;
  final int attempt; // 第几次重试（从 1 开始）
  final String reason; // "502" / "connectionError" 等
  final int waitMs; // 还会等多少毫秒
  RetryEvent(this.path, this.attempt, this.reason, this.waitMs);
}

class ApiService {
  // 默认 API 基础 URL
  // 优先级：运行时 setBaseUrl()（登录页"服务器地址"）> 编译期 --dart-define=API_BASE_URL > 占位地址
  // 自建部署打包示例：
  //   flutter build apk --release --dart-define=API_BASE_URL=https://你的服务器IP:9304
  static const String _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://your-server-ip:9304',
  );

  final Dio _dio;

  // 运行时地址（登录页可修改）
  String _baseUrl = _defaultBaseUrl;

  // 重试事件广播（UI 层监听显示提示）
  final StreamController<RetryEvent> _retryController = StreamController.broadcast();

  /// 网络重试事件流（broadcast，多个页面可同时监听）
  Stream<RetryEvent> get retryEvents => _retryController.stream;

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
      // 连接超时要短：快速失败让重试接管（frp 隧道/服务器宕机时，
      // 等 8s 还连不上就认为不可达，不要傻等 30s）
      client.connectionTimeout = const Duration(seconds: 8);
      return client;
    };
    _dio.httpClientAdapter = ioAdapter;

    _dio.options.baseUrl = _baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 8);
    _dio.options.receiveTimeout = const Duration(seconds: 15);

    // 添加日志拦截器
    _dio.interceptors.add(LogInterceptor(
      request: kDebugMode,
      requestBody: false,
      responseBody: false,
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

    // 网络抖动自动重试（仅 GET 幂等请求）
    // 场景：frp 隧道瞬断 / Nginx 返回 502 / 宽带瞬时抖动
    // 策略：前两次快速重试（500ms、2s），第三次等 5s，最多 3 次
    //       累计等待仅 7.5 秒，失败就立刻显示错误页让用户手动点重试，
    //       不傻等 46 秒让用户盯着转圈
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (error, handler) async {
        final options = error.requestOptions;
        final isGet = options.method.toUpperCase() == 'GET';
        const retryableTypes = [
          DioExceptionType.connectionTimeout,
          DioExceptionType.connectionError,
          DioExceptionType.receiveTimeout,
          DioExceptionType.badResponse,
        ];
        final status = error.response?.statusCode;
        final retryableStatus = status == 502 || status == 503 || status == 504;
        final canRetry = isGet &&
            retryableTypes.contains(error.type) &&
            (error.type != DioExceptionType.badResponse || retryableStatus);

        const delays = [
          Duration(milliseconds: 500),
          Duration(seconds: 2),
          Duration(seconds: 5),
        ];
        final attempt = (options.extra['retry_attempt'] as int?) ?? 0;

        if (canRetry && attempt < delays.length) {
          final delayMs = delays[attempt].inMilliseconds;
          final reason = status != null ? status.toString() : error.type.name;
          debugPrint('🔄 网络请求失败($reason)，'
              '${delays[attempt].inMilliseconds}ms 后第 ${attempt + 1} 次重试: ${options.path}');
          _retryController.add(RetryEvent(options.path, attempt + 1, reason, delayMs));
          await Future.delayed(delays[attempt]);
          options.extra['retry_attempt'] = attempt + 1;
          try {
            final response = await _dio.fetch(options);
            debugPrint('✅ 重试成功: ${options.path}');
            return handler.resolve(response);
          } catch (e) {
            return handler.next(e is DioException ? e : error);
          }
        }
        if (canRetry && attempt >= delays.length) {
          debugPrint('❌ 已达最大重试次数，放弃: ${options.path}');
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

  Future<void> updateLog(int logId, ConstructionLog log) async {
    try {
      final formData = FormData();
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

      await _dio.put('/api/logs/$logId', data: formData);
    } catch (e) {
      debugPrint('Error updating log: $e');
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
