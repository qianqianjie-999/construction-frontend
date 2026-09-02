import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'api_service.dart';
import 'auth_service.dart';

typedef MessageHandler = void Function(Map<String, dynamic> message);
typedef VoidHandler = void Function();
typedef ErrorHandler = void Function(String message);

/// Socket.IO 客户端封装
class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  bool _connected = false;
  bool get isConnected => _connected;

  final Set<MessageHandler> _messageHandlers = {};
  final Set<VoidHandler> _connectHandlers = {};
  final Set<VoidHandler> _disconnectHandlers = {};
  final Set<ErrorHandler> _errorHandlers = {};

  /// 连接 Socket.IO
  void connect() {
    if (_socket != null) return;
    final user = AuthService().currentUser;
    if (user == null) return;

    final base = ApiService.instance.baseUrl;

    // 去掉 http/https 前缀，得到 host:port，并推导出正确的 ws/wss 协议
    var uri = base.replaceFirst(RegExp(r'^https?://'), '');
    final isHttps = base.startsWith('https://');
    final proto = isHttps ? 'https' : 'http';

    _socket = IO.io(
      '$proto://$uri',
      IO.OptionBuilder()
          .setTransports(['polling'])  // Werkzeug 开发服务器不支持 websocket，使用 polling
          .disableAutoConnect()
          .setExtraHeaders({'Authorization': 'Bearer ${user.token}'})
          .build(),
    );

    _socket!.onConnect((_) {
      _connected = true;
      for (final h in _connectHandlers.toList()) {
        h();
      }
    });

    _socket!.onDisconnect((_) {
      _connected = false;
      for (final h in _disconnectHandlers.toList()) {
        h();
      }
    });

    _socket!.onConnectError((err) {
      for (final h in _errorHandlers.toList()) {
        h('connect_error: $err');
      }
    });

    _socket!.onError((err) {
      for (final h in _errorHandlers.toList()) {
        h('error: $err');
      }
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

  /// 转发日志卡片
  void sendLogCard(int projectId, int logId) {
    _socket?.emit('send_message', {
      'project_id': projectId,
      'content_type': 'log_card',
      'log_id': logId,
    });
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
    _connectHandlers.clear();
    _disconnectHandlers.clear();
    _errorHandlers.clear();
  }
}
