import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../services/auth_service.dart';

/// 聊天消息气泡
class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onLogCardTap;
  final ValueChanged<String>? onImageTap;
  final ValueChanged<String>? onImageLongPress;

  const MessageBubble({
    super.key,
    required this.message,
    this.onLogCardTap,
    this.onImageTap,
    this.onImageLongPress,
  });

  bool get _isMine {
    final me = AuthService().currentUser;
    return me != null && me.id == message.userId;
  }

  @override
  Widget build(BuildContext context) {
    final isMine = _isMine;
    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleColor = isMine ? const Color(0xFF00d4ff) : const Color(0xFF1a2332);
    final textColor = isMine ? const Color(0xFF0a0f1a) : const Color(0xFFf1f5f9);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine) _avatar(),
          Expanded(
            child: Column(
              crossAxisAlignment: align,
              children: [
                if (!isMine)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 2),
                    child: Text(
                      message.nickname,
                      style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 12),
                    ),
                  ),
                Container(
                  constraints: const BoxConstraints(maxWidth: 280),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(12),
                      topRight: const Radius.circular(12),
                      bottomLeft: Radius.circular(isMine ? 12 : 2),
                      bottomRight: Radius.circular(isMine ? 2 : 12),
                    ),
                  ),
                  child: _content(textColor, context),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2, right: 8),
                  child: Text(
                    _formatTime(message.createdAt),
                    style: const TextStyle(color: Color(0xFF64748b), fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
          if (isMine) _avatar(),
        ],
      ),
    );
  }

  Widget _avatar() {
    return Container(
      width: 36,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF00d4ff).withOpacity(0.2),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          message.nickname.isNotEmpty ? message.nickname.characters.first : '?',
          style: const TextStyle(color: Color(0xFF00d4ff), fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _content(Color textColor, BuildContext context) {
    switch (message.contentType) {
      case 'image':
        final url = message.content ?? '';
        if (url.isEmpty) return const SizedBox.shrink();
        final fullUrl = Uri.parse(
          url.startsWith('http') ? url : ChatService().imageUrl(url),
        ).toString();
        return GestureDetector(
          onTap: () => onImageTap?.call(fullUrl),
          onLongPress: () => onImageLongPress?.call(fullUrl),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220, maxHeight: 320),
              child: Image.network(
                fullUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  width: 200,
                  height: 100,
                  color: Colors.black26,
                  child: const Icon(Icons.broken_image, color: Color(0xFF94a3b8)),
                ),
              ),
            ),
          ),
        );
      case 'log_card':
        return GestureDetector(
          onTap: onLogCardTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0a0f1a).withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: textColor.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.description, size: 32, color: Color(0xFF00d4ff)),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('施工日志', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                    Text('点击查看', style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        );
      case 'text':
      default:
        return Text(
          message.content ?? '',
          style: TextStyle(color: textColor, fontSize: 14, height: 1.4),
        );
    }
  }

  String _formatTime(String createdAt) {
    if (createdAt.isEmpty) return '';
    // 简化处理：取 HH:mm:ss 部分
    final parts = createdAt.split(' ');
    if (parts.length >= 2) return parts[1].substring(0, 5);
    return createdAt;
  }
}
