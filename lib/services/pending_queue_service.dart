import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/construction_log.dart';
import 'api_service.dart';
import 'chat_service.dart';
import 'socket_service.dart';

/// 判断异常是否为"网络类错误"（断网/超时/网关抖动）——这类错误保留在队列自动重发；
/// 其余错误（400/404/413/500 等）标记为失败，交用户处理，避免无限重试。
bool isNetworkError(Object? e) {
  if (e is DioException) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return true;
      default:
        break;
    }
    final s = e.response?.statusCode;
    return s == 502 || s == 503 || s == 504;
  }
  return false;
}

/// 队列条目类型
class PendingType {
  static const chatText = 'chat_text';
  static const chatImage = 'chat_image';
  static const chatFile = 'chat_file';
  static const chatLocation = 'chat_location';
  static const log = 'log';
}

/// 一条待发记录。payload 按 type 区分：
/// - chat_text:     {'text': String}
/// - chat_image:    {'file': 'files/xx.jpg', 'filename': String}
/// - chat_file:     {'file': 'files/xx.doc', 'name': String, 'size': int}
/// - chat_location: {'lat': double, 'lng': double, 'text': String}
/// - log:           {'log': <ConstructionLog.toJson>, 'photos': ['files/...'],
///                   'certificates': ['files/...']}
class PendingItem {
  final String id;
  final String type;
  final int projectId;
  final DateTime createdAt;
  String status; // pending / sending / failed
  int attempts;
  String? failReason;
  final Map<String, dynamic> payload;

  PendingItem({
    required this.id,
    required this.type,
    required this.projectId,
    required this.createdAt,
    required this.status,
    required this.attempts,
    required this.payload,
    this.failReason,
  });

  bool get isChat => type.startsWith('chat_');
  bool get isPending => status == 'pending';
  bool get isSending => status == 'sending';
  bool get isFailed => status == 'failed';

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'project_id': projectId,
        'created_at': createdAt.toIso8601String(),
        'status': status,
        'attempts': attempts,
        'fail_reason': failReason,
        'payload': payload,
      };

  factory PendingItem.fromJson(Map<String, dynamic> json) {
    return PendingItem(
      id: json['id'] as String,
      type: json['type'] as String,
      projectId: json['project_id'] as int,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      status: json['status'] as String? ?? 'pending',
      attempts: json['attempts'] as int? ?? 0,
      failReason: json['fail_reason'] as String?,
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
    );
  }
}

/// 离线待发队列：
/// 断网时聊天文字/图片/文件/位置、施工日志先持久化到本机，
/// 网络恢复（connectivity 回调 / socket 重连 / App 回前台）后串行自动发送。
/// 数据按用户 ID 隔离存放在应用文档目录，杀进程也不丢。
class PendingQueueService extends ChangeNotifier with WidgetsBindingObserver {
  static final PendingQueueService _instance = PendingQueueService._internal();
  factory PendingQueueService() => _instance;
  PendingQueueService._internal();

  int? _userId;
  Directory? _baseDir;
  final List<PendingItem> _items = [];
  bool _flushing = false;
  bool _triggersReady = false;
  // 持有订阅引用，防止流订阅被垃圾回收（忽略未读取告警）
  // ignore: unused_field
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _socketHandlerRegistered = false;

  // ---------- 查询 ----------

  /// 某项目的待发聊天项（按时间升序）
  List<PendingItem> chatItemsFor(int projectId) => _items
      .where((e) => e.projectId == projectId && e.isChat)
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// 某项目的待发日志
  List<PendingItem> logItemsFor(int projectId) => _items
      .where((e) => e.projectId == projectId && e.type == PendingType.log)
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  int get totalCount => _items.length;

  // ---------- 生命周期 ----------

  /// 登录（或启动恢复登录态）后调用：加载该用户的队列并尝试发送
  Future<void> startForUser(int userId) async {
    _userId = userId;
    WidgetsBinding.instance.addObserver(this);
    _ensureTriggers();
    await _load();
    notifyListeners();
    kick();
  }

  /// 登出/切换账号：停止处理（磁盘数据保留，下次该账号登录继续发）
  Future<void> clearForUser() async {
    _userId = null;
    _items.clear();
    notifyListeners();
  }

  void _ensureTriggers() {
    if (_triggersReady) return;
    _triggersReady = true;

    // 系统网络变化
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) kick();
    });

    // socket 重连成功（聊天类消息依赖它）
    if (!_socketHandlerRegistered) {
      _socketHandlerRegistered = true;
      SocketService().onConnect(() => kick());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) kick();
  }

  // ---------- 持久化 ----------

  Future<Directory> _dir() async {
    if (_baseDir != null) return _baseDir!;
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/pending_queue/$_userId');
    await Directory('${d.path}/files').create(recursive: true);
    _baseDir = d;
    return d;
  }

  Future<File> _queueFile() async =>
      File('${(await _dir()).path}/queue.json');

  Future<void> _load() async {
    _items.clear();
    try {
      final f = await _queueFile();
      if (await f.exists()) {
        final list = jsonDecode(await f.readAsString()) as List;
        _items.addAll(
          list.map((e) => PendingItem.fromJson(e as Map<String, dynamic>)),
        );
      }
    } catch (e) {
      debugPrint('待发队列加载失败: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final f = await _queueFile();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(
        jsonEncode(_items.map((e) => e.toJson()).toList()),
        flush: true,
      );
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('待发队列保存失败: $e');
    }
  }

  String _newId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 32).toRadixString(16)}';
  }

  /// 复制/写入附件到队列目录，返回相对路径（files/xxx）
  Future<String> _storeBytes(Uint8List bytes, String ext) async {
    final d = await _dir();
    final name = '${_newId()}.$ext';
    final f = File('${d.path}/files/$name');
    await f.writeAsBytes(bytes, flush: true);
    return 'files/$name';
  }

  Future<String> _storeFile(File src) async {
    final d = await _dir();
    var ext = src.path.contains('.')
        ? src.path.split('.').last.toLowerCase()
        : 'jpg';
    if (ext.length > 8) ext = 'jpg';
    final name = '${_newId()}.$ext';
    final dst = File('${d.path}/files/$name');
    await src.copy(dst.path);
    return 'files/$name';
  }

  Future<String> _absPath(String rel) async => '${(await _dir()).path}/$rel';

  /// 条目关联本地文件的绝对路径（UI 显示待发图片/文件用）
  Future<String> localAbsolutePath(PendingItem item) async {
    final rel = item.payload['file'] as String? ?? '';
    return _absPath(rel);
  }

  Future<PendingItem> _add(String type, int projectId, Map<String, dynamic> payload) async {
    final item = PendingItem(
      id: _newId(),
      type: type,
      projectId: projectId,
      createdAt: DateTime.now(),
      status: 'pending',
      attempts: 0,
      payload: payload,
    );
    _items.add(item);
    await _persist();
    notifyListeners();
    kick();
    return item;
  }

  // ---------- 入队 API ----------

  Future<void> enqueueChatText(int projectId, String text) =>
      _add(PendingType.chatText, projectId, {'text': text});

  Future<void> enqueueChatLocation(int projectId,
      {required double lat, required double lng, String text = ''}) {
    return _add(PendingType.chatLocation, projectId, {
      'lat': lat,
      'lng': lng,
      'text': text,
    });
  }

  Future<void> enqueueChatImage(
      int projectId, Uint8List bytes, String filename) async {
    final rel = await _storeBytes(bytes, 'jpg');
    await _add(PendingType.chatImage, projectId, {
      'file': rel,
      'filename': filename,
    });
  }

  Future<void> enqueueChatFile(int projectId, File source,
      {required String name, required int size}) async {
    final rel = await _storeFile(source);
    await _add(PendingType.chatFile, projectId, {
      'file': rel,
      'name': name,
      'size': size,
    });
  }

  /// 日志入队：photos/certificates 为已经加好水印的 XFile
  Future<void> enqueueLog(
    ConstructionLog log,
    List<XFile> photos,
    List<XFile> certificates,
  ) async {
    final photoRels = <String>[];
    final certRels = <String>[];
    for (final x in photos) {
      final ext = x.name.contains('.') && x.name.split('.').last.length <= 8
          ? x.name.split('.').last
          : 'jpg';
      final rel = await _storeBytes(await x.readAsBytes(), ext);
      photoRels.add(rel);
    }
    for (final x in certificates) {
      final ext = x.name.contains('.') && x.name.split('.').last.length <= 8
          ? x.name.split('.').last
          : 'jpg';
      final rel = await _storeBytes(await x.readAsBytes(), ext);
      certRels.add(rel);
    }
    await _add(PendingType.log, log.projectId, {
      'log': log.toJson(),
      'photos': photoRels,
      'certificates': certRels,
    });
  }

  // ---------- 管理 ----------

  /// 删除条目并清理其关联文件
  Future<void> remove(String id) async {
    final i = _items.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final item = _items.removeAt(i);
    await _cleanupFiles(item);
    await _persist();
    notifyListeners();
  }

  Future<void> _cleanupFiles(PendingItem item) async {
    Future<void> del(String? rel) async {
      if (rel == null || rel.isEmpty) return;
      try {
        final f = File(await _absPath(rel));
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }

    switch (item.type) {
      case PendingType.chatImage:
      case PendingType.chatFile:
        await del(item.payload['file'] as String?);
        break;
      case PendingType.log:
        for (final k in ['photos', 'certificates']) {
          for (final rel in (item.payload[k] as List? ?? [])) {
            await del(rel as String);
          }
        }
        break;
      default:
        break;
    }
  }

  /// 手动重试失败项
  Future<void> retry(String id) async {
    final item = _items.firstWhere((e) => e.id == id, orElse: () =>
        throw StateError('item not found'));
    item.status = 'pending';
    item.attempts = 0;
    item.failReason = null;
    await _persist();
    notifyListeners();
    kick();
  }

  // ---------- 发送引擎 ----------

  /// 尝试发送（网络恢复、入队、手动重试、回前台时调用）
  Future<void> kick() async {
    if (_userId == null) return;
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.every((r) => r == ConnectivityResult.none)) return;
    } catch (_) {
      return;
    }
    unawaited(_flush());
  }

  bool _canDispatchNow(PendingItem item) {
    // 聊天类需要 socket 在线（图片虽先走 HTTP，但最终要 emit，
    // 统一要求在线，避免上传成功却发不出消息产生孤儿图）
    if (item.isChat) return SocketService().isConnected;
    return true;
  }

  Future<void> _flush() async {
    if (_flushing || _userId == null) return;
    _flushing = true;
    try {
      // 有待发聊天项且 socket 未连：拉起连接，连上后 onConnect 会再触发
      final hasChat = _items.any((e) => e.isChat && e.status == 'pending');
      if (hasChat && !SocketService().isConnected) {
        SocketService().connect();
      }

      bool changed = true;
      while (changed) {
        changed = false;
        PendingItem? next;
        for (final item in _items) {
          if (item.status == 'pending' && _canDispatchNow(item)) {
            next = item;
            break;
          }
        }
        if (next == null) break;

        next.status = 'sending';
        next.failReason = null;
        await _persist();
        notifyListeners();

        try {
          await _dispatch(next);
          final i = _items.indexWhere((e) => e.id == next!.id);
          if (i >= 0) {
            final done = _items.removeAt(i);
            await _cleanupFiles(done);
          }
          await _persist();
          notifyListeners();
          changed = true;
        } catch (e) {
          next.attempts += 1;
          if (isNetworkError(e)) {
            // 网络问题：保留待发，等下次网络事件，本轮停止（后面的大概率也失败）
            next.status = 'pending';
            next.failReason = '网络异常，恢复后自动重发';
            await _persist();
            notifyListeners();
            break;
          } else {
            // 内容/服务端错误：标记失败，不阻塞其他条目
            next.status = 'failed';
            next.failReason = _friendlyError(e);
            await _persist();
            notifyListeners();
          }
        }
      }
    } finally {
      _flushing = false;
      notifyListeners();
    }
  }

  String _friendlyError(Object e) {
    if (e is DioException) {
      final s = e.response?.statusCode;
      if (s == 413) return '文件超过服务器限制（100MB）';
      if (s == 401) return '登录已失效，请退出后重新登录';
      if (s == 404) return '项目不存在或已被删除';
      if (s != null) return '服务器返回错误（HTTP $s）';
      return '发送失败：${e.type.name}';
    }
    final msg = e.toString();
    return msg.length > 60 ? '${msg.substring(0, 60)}…' : msg;
  }

  Future<void> _dispatch(PendingItem item) async {
    switch (item.type) {
      case PendingType.chatText:
        SocketService().sendText(item.projectId, item.payload['text'] as String);
        break;

      case PendingType.chatLocation:
        SocketService().sendLocation(
          item.projectId,
          lat: (item.payload['lat'] as num).toDouble(),
          lng: (item.payload['lng'] as num).toDouble(),
          text: item.payload['text'] as String? ?? '',
        );
        break;

      case PendingType.chatImage:
        final bytes = await File(await _absPath(item.payload['file'] as String))
            .readAsBytes();
        final filename = item.payload['filename'] as String? ??
            'chat_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final result =
            await ChatService().uploadImage(Uint8List.fromList(bytes), filename);
        SocketService()
            .sendImage(item.projectId, result['filename'] as String);
        break;

      case PendingType.chatFile:
        final path = await _absPath(item.payload['file'] as String);
        final name = item.payload['name'] as String? ?? 'file';
        final meta = await ChatService().uploadFile(XFile(path, name: name));
        SocketService().sendFile(item.projectId, {
          'name': (meta['name'] ?? name).toString(),
          'path': (meta['filename'] ?? '').toString(),
          'size':
              (meta['size'] is num) ? (meta['size'] as num).toInt() : item.payload['size'] ?? 0,
        });
        break;

      case PendingType.log:
        final log = ConstructionLog.fromJson(
          Map<String, dynamic>.from(item.payload['log'] as Map),
        );
        final photos = <XFile>[
          for (final rel in (item.payload['photos'] as List? ?? const []))
            XFile(await _absPath(rel as String)),
        ];
        final certs = <XFile>[
          for (final rel in (item.payload['certificates'] as List? ?? const []))
            XFile(await _absPath(rel as String)),
        ];
        await ApiService().createLog(log, photos, certs);
        break;
    }
  }
}
