import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../models/project.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/image_save_service.dart';
import '../services/socket_service.dart';
import '../services/watermark_service.dart';
import '../widgets/chat_context_viewer.dart';
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
  bool _uploading = false;
  int? _oldestId;
  bool _connected = false;

  // 搜索状态
  bool _searchMode = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<ChatMessage> _searchResults = [];
  bool _searching = false;
  String _searchKeyword = '';

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
    _searchDebounce?.cancel();
    _searchController.dispose();
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

  /// 选择并发送文件（word/excel/ppt/pdf/dwg 等，白名单与服务端一致）
  Future<void> _pickAndSendFile() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'pdf',
          'dwg', 'dxf', 'txt', 'csv', 'md', 'zip', 'rar', '7z',
        ],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开文件选择器: $e')),
        );
      }
      return;
    }
    final picked = result?.files.single;
    if (picked == null || picked.path == null) return;

    final file = File(picked.path!);
    int len = 0;
    try {
      len = await file.length();
    } catch (_) {}
    if (len > 100 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件超过 100MB 上限，请压缩后重试')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _uploading = true);
    try {
      final meta = await ChatService().uploadFile(XFile(picked.path!, name: picked.name));
      SocketService().sendFile(widget.project.id, {
        'name': (meta['name'] ?? picked.name).toString(),
        'path': (meta['filename'] ?? '').toString(),
        'size': (meta['size'] is num) ? (meta['size'] as num).toInt() : len,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('文件上传失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
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
        actions: [
          IconButton(
            onPressed: _toggleSearch,
            icon: Icon(_searchMode ? Icons.chat_bubble_outline : Icons.search,
                color: const Color(0xFF00d4ff)),
            tooltip: _searchMode ? '返回聊天' : '搜索聊天记录',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_searchMode) _searchHeader(),
          Expanded(child: _searchMode ? _searchResultsView() : _chatListView()),
          if (!_searchMode) ...[
            if (_loading || _uploading) const LinearProgressIndicator(color: Color(0xFF00d4ff)),
            _inputBar(),
          ],
        ],
      ),
    );
  }

  /// 正常聊天视图（加载更多 + 消息列表）
  Widget _chatListView() {
    return Column(
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
                onImageLongPress: (url) => _saveImage(url),
                onFileTap: (msg) => _downloadAndOpen(msg),
              );
            },
          ),
        ),
      ],
    );
  }

  /* ============ 聊天记录搜索 ============ */

  void _toggleSearch() {
    setState(() => _searchMode = !_searchMode);
    if (!_searchMode) _searchController.clear();
    _searchResults = [];
    _searching = false;
    _searchKeyword = '';
  }

  Widget _searchHeader() {
    return Container(
      color: const Color(0xFF1a2332),
      padding: const EdgeInsets.only(left: 4, right: 8, top: 4, bottom: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: _toggleSearch,
            icon: const Icon(Icons.arrow_back, color: Color(0xFF00d4ff), size: 20),
            tooltip: '退出搜索',
          ),
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: Color(0xFFf1f5f9), fontSize: 14),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索消息 / 文件名 / 发送人…',
                hintStyle: const TextStyle(color: Color(0xFF64748b)),
                filled: true,
                fillColor: const Color(0xFF0a0f1a),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF64748b), size: 18),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: _searchKeyword.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, color: Color(0xFF64748b), size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      ),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(value.trim());
    });
    if (value.trim().isEmpty) {
      _searchDebounce?.cancel();
      setState(() {
        _searchResults = [];
        _searching = false;
        _searchKeyword = '';
      });
    }
  }

  Future<void> _runSearch(String keyword) async {
    if (keyword.isEmpty) return;
    setState(() {
      _searching = true;
      _searchKeyword = keyword;
    });
    try {
      final results = await ChatService().searchMessages(widget.project.id, keyword);
      if (!mounted) return;
      // 丢弃过期结果（关键词已变化）
      if (_searchController.text.trim() != keyword) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _searching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('搜索失败: $e')),
      );
    }
  }

  Widget _searchResultsView() {
    if (_searching) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00d4ff)));
    }
    if (_searchKeyword.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, color: Color(0xFF334155), size: 56),
            SizedBox(height: 12),
            Text('搜索当前项目全部聊天记录', style: TextStyle(color: Color(0xFF64748b), fontSize: 14)),
            SizedBox(height: 4),
            Text('支持消息内容、文件名、发送人', style: TextStyle(color: Color(0xFF475569), fontSize: 12)),
          ],
        ),
      );
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, color: Color(0xFF334155), size: 56),
            const SizedBox(height: 12),
            Text('未找到与「$_searchKeyword」相关的消息',
                style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 14)),
            const SizedBox(height: 4),
            const Text('试试换关键词，或搜索发送人昵称', style: TextStyle(color: Color(0xFF475569), fontSize: 12)),
          ],
        ),
      );
    }
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: const Color(0xFF0f172a),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            '共 ${_searchResults.length} 条结果（搜索全量历史，最多展示 50 条）',
            style: const TextStyle(color: Color(0xFF00d4ff), fontSize: 12),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: _searchResults.length,
            itemBuilder: (context, index) {
              final m = _searchResults[index];
              return _searchTile(m);
            },
          ),
        ),
      ],
    );
  }

  Widget _searchTile(ChatMessage m) {
    final preview = _messagePreview(m);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: const Color(0xFF00d4ff).withOpacity(0.15),
        child: Text(
          m.nickname.isNotEmpty ? m.nickname.characters.first : '?',
          style: const TextStyle(color: Color(0xFF00d4ff), fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text.rich(
        TextSpan(
          children: _highlightSpans(
            preview,
            _searchKeyword,
            const TextStyle(color: Color(0xFFf1f5f9), fontSize: 14),
          ),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          '${m.nickname} · ${_shortTime(m.createdAt)} · ${_typeLabel(m.contentType)}',
          style: const TextStyle(color: Color(0xFF64748b), fontSize: 12),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: Color(0xFF334155), size: 20),
      onTap: () => _openContext(m),
    );
  }

  /// 打开命中消息的上下文定位页
  void _openContext(ChatMessage m) {
    final id = m.id;
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatContextViewer(
          projectId: widget.project.id,
          projectName: widget.project.name,
          anchorId: id,
        ),
      ),
    );
  }

  /// 搜索命中高亮文本片段构造
  List<TextSpan> _highlightSpans(String text, String keyword, TextStyle style) {
    if (keyword.isEmpty || text.isEmpty) return [TextSpan(text: text, style: style)];
    final lower = text.toLowerCase();
    final lq = keyword.toLowerCase();
    final spans = <TextSpan>[];
    var i = 0;
    while (i < text.length) {
      final idx = lower.indexOf(lq, i);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(i), style: style));
        break;
      }
      if (idx > i) spans.add(TextSpan(text: text.substring(i, idx), style: style));
      spans.add(TextSpan(
        text: text.substring(idx, idx + keyword.length),
        style: style.copyWith(
          color: const Color(0xFF713f12),
          backgroundColor: const Color(0xFFfde047),
          fontWeight: FontWeight.bold,
        ),
      ));
      i = idx + keyword.length;
    }
    return spans;
  }

  String _messagePreview(ChatMessage m) {
    switch (m.contentType) {
      case 'image':
        return '🖼 图片消息';
      case 'log_card':
        return '📋 施工日志卡片';
      case 'file':
        try {
          final raw = jsonDecode(m.content ?? '');
          if (raw is Map) {
            final name = (raw['name'] ?? raw['path'] ?? '文件').toString();
            return '📎 $name';
          }
        } catch (_) {}
        return '📎 文件消息';
      default:
        return m.content ?? '';
    }
  }

  String _typeLabel(String contentType) {
    switch (contentType) {
      case 'image':
        return '图片';
      case 'file':
        return '文件';
      case 'log_card':
        return '日志卡片';
      default:
        return '文本';
    }
  }

  String _shortTime(String createdAt) {
    if (createdAt.isEmpty) return '';
    final parts = createdAt.split(' ');
    if (parts.length >= 2) {
      final date = parts[0].substring(5); // MM-dd
      final time = parts[1].length >= 5 ? parts[1].substring(0, 5) : parts[1];
      return '$date $time';
    }
    return createdAt;
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
            onPressed: _uploading ? null : _pickAndSendFile,
            icon: const Icon(Icons.attach_file, color: Color(0xFF00d4ff)),
            tooltip: '发送文件',
          ),
          IconButton(
            onPressed: _uploading ? null : _pickAndSendImage,
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
            actions: [
              IconButton(
                icon: const Icon(Icons.download, color: Colors.white),
                onPressed: () => _saveImage(url),
                tooltip: '保存到相册',
              ),
            ],
          ),
          body: Center(
            child: GestureDetector(
              onLongPress: () => _saveImage(url),
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
      ),
    );
  }

  /// 保存图片到相册
  Future<void> _saveImage(String url) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在保存...'), duration: Duration(seconds: 1)),
    );
    final (success, msg) = await ImageSaveService().saveFromUrl(url);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? const Color(0xFF4CAF50) : const Color(0xFFef4444),
      ),
    );
  }

  /// 点击文件消息：已下载过则直接打开，否则先下载到应用文档目录再打开
  Future<void> _downloadAndOpen(ChatMessage msg) async {
    Map<String, dynamic>? meta;
    try {
      final raw = jsonDecode(msg.content ?? '');
      if (raw is Map) meta = Map<String, dynamic>.from(raw);
    } catch (_) {}
    final path = (meta?['path'] ?? '').toString();
    if (path.isEmpty) return;
    final name = (meta?['name'] ?? path).toString();

    final dir = await getApplicationDocumentsDirectory();
    final savePath = '${dir.path}${Platform.pathSeparator}$path';

    if (File(savePath).existsSync()) {
      await OpenFilex.open(savePath);
      return;
    }
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DownloadDialog(
        url: ChatService().fileUrl(path, name: name),
        savePath: savePath,
        fileName: name,
      ),
    );
  }
}

/// 文件下载进度对话框：下载完成后自动关闭并调用系统应用打开
class _DownloadDialog extends StatefulWidget {
  final String url;
  final String savePath;
  final String fileName;

  const _DownloadDialog({
    required this.url,
    required this.savePath,
    required this.fileName,
  });

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  double _progress = 0;
  String _status = '连接中...';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiService.instance.dio.download(
        widget.url,
        widget.savePath,
        options: Options(receiveTimeout: const Duration(minutes: 10)),
        onReceiveProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            if (total > 0) {
              _progress = received / total;
              _status = '下载中 ${(received / 1048576).toStringAsFixed(1)} / '
                  '${(total / 1048576).toStringAsFixed(1)} MB';
            } else {
              _status = '下载中 ${(received / 1048576).toStringAsFixed(1)} MB ...';
            }
          });
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      final result = await OpenFilex.open(widget.savePath);
      if (result.type != ResultType.done) {
        messenger.showSnackBar(
          const SnackBar(content: Text('文件已下载，但本机暂无应用可打开，可在系统文件管理器中查看')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text('文件下载失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1a2332),
      title: Text(
        widget.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Color(0xFFf1f5f9), fontSize: 15),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: _progress <= 0 ? null : _progress,
            color: const Color(0xFF00d4ff),
            backgroundColor: const Color(0xFF334155),
          ),
          const SizedBox(height: 12),
          Text(_status, style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 12)),
        ],
      ),
    );
  }
}
