import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/project.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/socket_service.dart';
import '../services/watermark_service.dart';
import '../widgets/message_bubble.dart';

/// 聊天主界面
class ChatScreen extends StatefulWidget {
  final Project project;
  final int? initialLogId; // 从日志详情转发时传入

  const ChatScreen({super.key, required this.project, this.initialLogId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _loading = false;
  bool _hasMore = true;
  int? _oldestId;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadHistory();
    _setupSocket();
    if (widget.initialLogId != null) {
      SocketService().sendLogCard(widget.project.id, widget.initialLogId!);
    }
  }

  @override
  void dispose() {
    SocketService().leaveProject(widget.project.id);
    SocketService().offMessage(_onReceiveMessage);
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory({bool refresh = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final msgs = await ChatService().getMessages(
        widget.project.id,
        beforeId: refresh ? null : _oldestId,
      );
      if (msgs.isEmpty) {
        _hasMore = false;
      } else {
        if (refresh) {
          _messages.clear();
        } else {
          // 滚动位置保持
          final oldScrollOffset = _scrollController.hasClients ? _scrollController.offset : 0;
          // 在前面插入
          _messages.insertAll(0, msgs.reversed);
          _oldestId = msgs.first.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              final newMax = _scrollController.position.maxScrollExtent;
              final estimated = oldScrollOffset + 400.0; // 估算
              _scrollController.jumpTo(estimated.clamp(0, newMax));
            }
          });
        }
        if (msgs.length < 30) _hasMore = false;
        if (_messages.isNotEmpty) {
          _oldestId = _messages.first.id;
        }
        if (refresh || _messages.length == msgs.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }
      }
      _markAllRead();
    } catch (e) {
      debugPrint('load history error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setupSocket() {
    final socket = SocketService();
    socket.offMessage(_onReceiveMessage);
    socket.onMessage(_onReceiveMessage);
    socket.onConnect(() {
      if (!mounted) return;
      setState(() => _connected = true);
      socket.joinProject(widget.project.id);
    });
    socket.onDisconnect(() {
      if (!mounted) return;
      setState(() => _connected = false);
    });
    socket.onError((msg) {
      debugPrint('socket error: $msg');
    });
    if (!socket.isConnected) {
      socket.connect();
    } else {
      setState(() => _connected = true);
      socket.joinProject(widget.project.id);
    }
  }

  void _onReceiveMessage(Map<String, dynamic> data) {
    final msg = ChatMessage.fromJson(data);
    if (msg.projectId != widget.project.id) return;
    // 避免重复
    if (msg.id != null && _messages.any((m) => m.id == msg.id)) return;
    setState(() {
      _messages.add(msg);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    _markAllRead();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _markAllRead() async {
    final me = AuthService().currentUser;
    if (me == null) return;
    final unreadIds = _messages
        .where((m) => m.id != null && m.userId != me.id && !m.isReadByMe)
        .map((m) => m.id!)
        .toList();
    if (unreadIds.isEmpty) return;
    SocketService().markRead(unreadIds);
    setState(() {
      for (final m in _messages) {
        if (unreadIds.contains(m.id)) {
          // 标记已读
          final idx = _messages.indexOf(m);
          _messages[idx] = ChatMessage(
            id: m.id, projectId: m.projectId, userId: m.userId,
            username: m.username, nickname: m.nickname, avatar: m.avatar,
            contentType: m.contentType, content: m.content, logId: m.logId,
            createdAt: m.createdAt, isReadByMe: true,
          );
        }
      }
    });
  }

  void _sendText() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    SocketService().sendText(widget.project.id, text);
    _inputController.clear();
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (xfile == null) return;
    final bytes = await xfile.readAsBytes();
    // 压缩图片：限制尺寸 1280px + 质量 70，适配低带宽
    final compressed = await WatermarkService().compressBytes(bytes);
    final uint8Bytes = Uint8List.fromList(compressed);
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final result = await ChatService().uploadImage(uint8Bytes, 'chat_${DateTime.now().millisecondsSinceEpoch}.jpg');
      final filename = result['filename'] as String;
      SocketService().sendImage(widget.project.id, filename);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片上传失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0f1a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a2332),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.project.name,
              style: const TextStyle(color: Color(0xFFf1f5f9), fontSize: 16),
            ),
            Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: _connected ? const Color(0xFF22c55e) : const Color(0xFF94a3b8),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _connected ? '已连接' : '连接中...',
                  style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Color(0xFF00d4ff)),
      ),
      body: Column(
        children: [
          if (_hasMore)
            TextButton(
              onPressed: _loading ? null : () => _loadHistory(),
              child: const Text('加载更多', style: TextStyle(color: Color(0xFF00d4ff))),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final m = _messages[index];
                return MessageBubble(
                  message: m,
                  onLogCardTap: () => _showLogCard(m.logId),
                  onImageTap: (url) => _showFullImage(url),
                );
              },
            ),
          ),
          if (_loading) const LinearProgressIndicator(color: Color(0xFF00d4ff)),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF1a2332),
        border: Border(top: BorderSide(color: Color(0xFF334155))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _pickAndSendImage,
            icon: const Icon(Icons.image, color: Color(0xFF00d4ff)),
          ),
          Expanded(
            child: TextField(
              controller: _inputController,
              style: const TextStyle(color: Color(0xFFf1f5f9)),
              decoration: InputDecoration(
                hintText: '输入消息...',
                hintStyle: const TextStyle(color: Color(0xFF64748b)),
                filled: true,
                fillColor: const Color(0xFF0a0f1a),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _sendText(),
            ),
          ),
          IconButton(
            onPressed: _sendText,
            icon: const Icon(Icons.send, color: Color(0xFF00d4ff)),
          ),
        ],
      ),
    );
  }

  void _showLogCard(int? logId) {
    if (logId == null) return;
    // 简化：弹出小提示，可在后续接入日志详情页
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1a2332),
        title: const Text('施工日志', style: TextStyle(color: Color(0xFFf1f5f9))),
        content: Text('日志 ID: $logId', style: const TextStyle(color: Color(0xFF94a3b8))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭', style: TextStyle(color: Color(0xFF00d4ff))),
          ),
        ],
      ),
    );
  }

  void _showFullImage(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(url, loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return CircularProgressIndicator(
                  value: progress.cumulativeBytesLoaded / (progress.expectedTotalBytes ?? 1),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
