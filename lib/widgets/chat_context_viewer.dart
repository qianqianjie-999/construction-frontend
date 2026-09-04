import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import 'message_bubble.dart';

/// 聊天搜索：命中消息的上下文定位页
/// 围绕 anchorId 加载前后各若干条消息（服务端 around_id 窗口），
/// 整页一次性构建（消息量小），打开后自动滚动到命中消息并高亮。
class ChatContextViewer extends StatefulWidget {
  final int projectId;
  final String projectName;
  final int anchorId;

  const ChatContextViewer({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.anchorId,
  });

  @override
  State<ChatContextViewer> createState() => _ChatContextViewerState();
}

class _ChatContextViewerState extends State<ChatContextViewer> {
  List<ChatMessage>? _messages;
  String? _error;
  final Map<int, GlobalKey> _keys = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final msgs = await ChatService().getMessages(
        widget.projectId,
        aroundId: widget.anchorId,
        limit: 21,
      );
      if (!mounted) return;
      setState(() => _messages = msgs);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToAnchor());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '加载失败: $e');
    }
  }

  void _scrollToAnchor() {
    final key = _keys[widget.anchorId];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignment: 0.3,
    );
  }

  void _showImage(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: InteractiveViewer(child: Image.network(url)),
            ),
          ),
        ),
      ),
    );
  }

  void _showFileHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('文件请返回聊天页面点击下载打开')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0f1a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a2332),
        iconTheme: const IconThemeData(color: Color(0xFF00d4ff)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('命中消息上下文',
                style: TextStyle(color: Color(0xFFf1f5f9), fontSize: 16)),
            Text(
              widget.projectName,
              style: const TextStyle(color: Color(0xFF64748b), fontSize: 11),
            ),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Text(_error!,
            style: const TextStyle(color: Color(0xFFef4444), fontSize: 14)),
      );
    }
    final msgs = _messages;
    if (msgs == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00d4ff)),
      );
    }
    if (msgs.isEmpty) {
      return const Center(
        child: Text('未找到该消息（可能已删除）',
            style: TextStyle(color: Color(0xFF94a3b8), fontSize: 14)),
      );
    }
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: const Color(0xFF0f172a),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: const Text(
            '▼ 黄色高亮为命中的消息，上下为聊天上下文',
            style: TextStyle(color: Color(0xFF94a3b8), fontSize: 12),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [for (final m in msgs) _buildItem(m)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItem(ChatMessage m) {
    final isAnchor = m.id == widget.anchorId;
    final key = _keys.putIfAbsent(m.id ?? m.hashCode, () => GlobalKey());
    return KeyedSubtree(
      key: key,
      child: MessageBubble(
        message: m,
        highlight: isAnchor,
        onLogCardTap: null,
        onImageTap: _showImage,
        onFileTap: (_) => _showFileHint(),
      ),
    );
  }
}
