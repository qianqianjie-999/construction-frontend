import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'api_service.dart';

/// 聊天消息
class ChatMessage {
  final int? id;
  final int projectId;
  final int userId;
  final String username;
  final String nickname;
  final String? avatar;
  final String contentType;  // text / image / log_card
  final String? content;
  final int? logId;
  final String createdAt;
  final bool isReadByMe;

  ChatMessage({
    this.id,
    required this.projectId,
    required this.userId,
    required this.username,
    required this.nickname,
    this.avatar,
    required this.contentType,
    this.content,
    this.logId,
    required this.createdAt,
    this.isReadByMe = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as int?,
      projectId: json['project_id'] as int,
      userId: json['user_id'] as int,
      username: json['username'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      avatar: json['avatar'] as String?,
      contentType: json['content_type'] as String? ?? 'text',
      content: json['content'] as String?,
      logId: json['log_id'] as int?,
      createdAt: json['created_at'] as String? ?? '',
      isReadByMe: json['is_read_by_me'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'project_id': projectId,
    'user_id': userId,
    'username': username,
    'nickname': nickname,
    'avatar': avatar,
    'content_type': contentType,
    'content': content,
    'log_id': logId,
    'created_at': createdAt,
  }
    ..removeWhere((k, v) => k == 'id' && id == null);
}

/// 聊天 REST 接口（历史消息、上传图片、已读、未读数）
class ChatService {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  Dio get _dio => ApiService.instance.dio;

  /// 获取历史消息（分页）
  Future<List<ChatMessage>> getMessages(int projectId, {int? beforeId, int limit = 30}) async {
    final params = <String, dynamic>{'project_id': projectId, 'limit': limit};
    if (beforeId != null) params['before_id'] = beforeId;
    final response = await _dio.get('/api/chat/messages', queryParameters: params);
    final list = response.data as List;
    return list.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 上传图片，返回文件名和服务端 url
  Future<Map<String, dynamic>> uploadImage(Uint8List bytes, String filename) async {
    final formData = FormData();
    formData.files.add(MapEntry('image', MultipartFile.fromBytes(bytes, filename: filename)));
    final response = await _dio.post('/api/chat/upload_image', data: formData);
    return response.data as Map<String, dynamic>;
  }

  /// 标记消息已读
  Future<void> markRead(int messageId) async {
    await _dio.post('/api/chat/messages/$messageId/read');
  }

  /// 获取所有项目群的未读数：{ project_id: count }
  Future<Map<int, int>> unreadCount() async {
    final response = await _dio.get('/api/chat/messages/unread_count');
    final data = response.data as Map<String, dynamic>;
    return data.map((k, v) => MapEntry(int.parse(k), v as int));
  }

  /// 图片完整 URL
  String imageUrl(String filename) {
    final base = ApiService.instance.baseUrl;
    return '$base/api/chat/images/$filename';
  }
}
