import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'api_service.dart';
import 'auth_service.dart';

typedef MessageHandler = void Function(Map<String, dynamic> message);
typedef VoidHandler = void Function();
typedef ErrorHandler = void Function(String message);
typedef RecallAckHandler = void Function(String requestId, bool success, String message);

/// Socket.IO 客户端封装
class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  bool _connected = false;
  bool get isConnected => _connected;

  final Set<MessageHandler> _messageHandlers = {};
  final Set<MessageHandler> _recallHandlers = {};
  final Set<RecallAckHandler> _recallAckHandlers = {};
  final Set<VoidHandler> _connectHandlers = {};
  final Set<VoidHandler> _disconnectHandlers = {};
  final Set<ErrorHandler> _errorHandlers = {};

  /// 连接 Socket.IO
  void connect() async {
    final user = AuthService().currentUser;
    if (user == null) return;

    // 已连接则跳过；若存在死连接（_socket 非空但未连接），先清理再重建
    if (_socket != null && _connected) return;
    if (_socket != null) {
      debugPrint('Socket.IO 检测到未连接 socket，重建中...');
      _socket!.dispose();
      _socket = null;
      _connected = false;
    }

    final base = ApiService.instance.baseUrl;

    // 去掉 http/https 前缀，得到 host:port，并推导出正确的 ws/wss 协议
    var uri = base.replaceFirst(RegExp(r'^https?://'), '');
    final isHttps = base.startsWith('https://');
    final proto = isHttps ? 'wss' : 'ws';

    final wsUrl = '$proto://$uri';
    debugPrint('Socket.IO 连接: $wsUrl (token=${user.token!.substring(0, 8)}...)');

    _socket = IO.io(
      wsUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])  // Android 只支持 WebSocket
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(1000000)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setExtraHeaders({'Authorization': 'Bearer ${user.token}'})
          .enableForceNewConnection()
          .build(),
    );

    _socket!.onConnect((_) {
      _connected = true;
      debugPrint('Socket.IO 连接成功！');
      for (final h in _connectHandlers.toList()) {
        h();
      }
    });

    _socket!.onDisconnect((reason) {
      _connected = false;
      debugPrint('Socket.IO 断开: $reason');
      for (final h in _disconnectHandlers.toList()) {
        h();
      }
    });

    _socket!.onConnectError((err) {
      debugPrint('Socket.IO connectError: $err');
      for (final h in _errorHandlers.toList()) {
        h('连接失败: $err');
      }
    });

    _socket!.onError((err) {
      debugPrint('Socket.IO error: $err');
      for (final h in _errorHandlers.toList()) {
        h('错误: $err');
      }
    });

    _socket!.on('connect_error', (data) {
      debugPrint('Socket.IO server connect_error: $data');
    });

    // 服务端 emit('receive_message', msg)
    _socket!.on('receive_message', (data) {
      if (data is Map) {
        final m = Map<String, dynamic>.from(data);
        for (final h in _messageHandlers.toList()) {
          h(m);
        }
      }
    });

    // 服务端 emit('message_recalled', {message_id, project_id})
    _socket!.on('message_recalled', (data) {
      if (data is Map) {
        final m = Map<String, dynamic>.from(data);
        for (final h in _recallHandlers.toList()) {
          h(m);
        }
      }
    });

    // 服务端 emit('recall_ack', {request_id, success, message})
    _socket!.on('recall_ack', (data) {
      debugPrint('[socket] recall_ack received: $data');
      if (data is Map) {
        final m = Map<String, dynamic>.from(data);
        final rid = (m['request_id'] ?? '').toString();
        final ok = m['success'] as bool? ?? false;
        final msg = (m['message'] ?? '').toString();
        for (final h in _recallAckHandlers.toList()) {
          h(rid, ok, msg);
        }
      }
    });

    _socket!.connect();
  }

  /// 加入项目群
  void joinProject(int projectId) {
    _socket?.emit('join_project', {'project_id': projectId});
  }

  /// 离开项目群
  void leaveProject(int projectId) {
    _socket?.emit('leave_project', {'project_id': projectId});
  }

  /// 发送文本消息
  void sendText(int projectId, String text) {
    _socket?.emit('send_message', {
      'project_id': projectId,
      'content_type': 'text',
      'content': text,
    });
  }

  /// 发送图片消息（filename 已通过 upload_image 上传获得）
  void sendImage(int projectId, String filename) {
    _socket?.emit('send_message', {
      'project_id': projectId,
      'content_type': 'image',
      'content': filename,
    });
  }

  /// 发送文件消息（meta 已通过 upload_file 上传获得：{name, path, size}）
  void sendFile(int projectId, Map<String, dynamic> meta) {
    _socket?.emit('send_message', {
      'project_id': projectId,
      'content_type': 'file',
      'content': jsonEncode(meta),
    });
  }

  /// 转发日志卡片
  void sendLogCard(int projectId, int logId) {
    _socket?.emit('send_message', {
      'project_id': projectId,
      'content_type': 'log_card',
      'log_id': logId,
    });
  }

  /// 发送定位（GCJ02 高德坐标，前端已做 WGS84→GCJ02 转换；text 为可选备注）
  void sendLocation(int projectId,
      {required double lat, required double lng, String text = ''}) {
    _socket?.emit('send_message', {
      'project_id': projectId,
      'content_type': 'location',
      'content': jsonEncode({'lat': lat, 'lng': lng, 'text': text}),
    });
  }

  /// 撤回消息（仅本人消息，2 分钟内）。带 request_id 便于 ack 确认。
  void recallMessage(int messageId, {String? requestId}) {
    final data = <String, dynamic>{'message_id': messageId};
    if (requestId != null) data['request_id'] = requestId;
    _socket?.emit('recall_message', data);
  }

  /// 注册撤回 ack 监听器（收到后端 recall_ack 时触发）
  void onRecallAck(RecallAckHandler h) {
    _recallAckHandlers.add(h);
  }

  void offRecallAck(RecallAckHandler h) {
    _recallAckHandlers.remove(h);
  }

  /// 批量标记已读
  void markRead(List<int> messageIds) {
    _socket?.emit('mark_read', {'message_ids': messageIds});
  }

  // 注册/注销监听器
  void onMessage(MessageHandler h) {
    _messageHandlers.add(h);
  }

  void offMessage(MessageHandler h) {
    _messageHandlers.remove(h);
  }

  void onRecall(MessageHandler h) {
    _recallHandlers.add(h);
  }

  void offRecall(MessageHandler h) {
    _recallHandlers.remove(h);
  }

  void onConnect(VoidHandler h) {
    _connectHandlers.add(h);
  }

  void onDisconnect(VoidHandler h) {
    _disconnectHandlers.add(h);
  }

  void onError(ErrorHandler h) {
    _errorHandlers.add(h);
  }

  /// 断开连接
  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connected = false;
    _messageHandlers.clear();
    _recallHandlers.clear();
    _recallAckHandlers.clear();
    _connectHandlers.clear();
    _disconnectHandlers.clear();
    _errorHandlers.clear();
  }
}
