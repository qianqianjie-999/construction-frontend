import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/chat_service.dart';
import '../services/auth_service.dart';

/// 聊天消息气泡
class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onLogCardTap;
  final ValueChanged<String>? onImageTap;
  final ValueChanged<String>? onImageLongPress;
  final ValueChanged<ChatMessage>? onFileTap;
  final ValueChanged<int>? onRecall;  // 撤回回调
  final bool highlight; // 搜索结果定位时高亮边框

  const MessageBubble({
    super.key,
    required this.message,
    this.onLogCardTap,
    this.onImageTap,
    this.onImageLongPress,
    this.onFileTap,
    this.onRecall,
    this.highlight = false,
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

    // 已撤回消息：显示灰色提示
    if (message.recalled) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isMine) _avatar(),
            Container(
              constraints: const BoxConstraints(maxWidth: 280),
              padding: const EdgeInsets.all(10),
              child: Text(
                '${isMine ? "你" : message.nickname}撤回了一条消息',
                style: const TextStyle(color: Color(0xFF64748b), fontSize: 13, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onLongPress: isMine && onRecall != null
          ? () => _showRecallMenu(context)
          : null,
      child: Container(
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
                      border: highlight
                          ? Border.all(color: const Color(0xFFfbbf24), width: 2)
                          : null,
                    ),
                    child: _content(textColor, context),
                  ),
                if (highlight)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2, right: 8),
                    child: Text(
                      '▼ 命中消息',
                      style: TextStyle(
                        color: const Color(0xFFfbbf24),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
      ),
    );
  }

  void _showImageMenu(BuildContext context, String url) {
    final actions = <Widget>[];
    // 自己的消息且可撤回 → 加撤回选项
    if (_isMine && onRecall != null && message.id != null) {
      actions.add(ListTile(
        leading: const Icon(Icons.undo, color: Color(0xFFef4444)),
        title: const Text('撤回消息', style: TextStyle(color: Color(0xFFef4444))),
        onTap: () {
          Navigator.pop(context);
          _showRecallMenu(context);
        },
      ));
    }
    // 所有人都能保存
    actions.add(ListTile(
      leading: const Icon(Icons.download, color: Color(0xFF00d4ff)),
      title: const Text('保存到相册', style: TextStyle(color: Color(0xFFf1f5f9))),
      onTap: () {
        Navigator.pop(context);
        onImageLongPress?.call(url);
      },
    ));

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a2332),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: actions,
        ),
      ),
    );
  }

  void _showRecallMenu(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a2332),
        title: const Text('消息操作', style: TextStyle(color: Color(0xFFf1f5f9))),
        content: const Text('确定要撤回这条消息吗？', style: TextStyle(color: Color(0xFF94a3b8))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Color(0xFF64748b))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onRecall?.call(message.id!);
            },
            child: const Text('撤回', style: TextStyle(color: Color(0xFFef4444), fontWeight: FontWeight.bold)),
          ),
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
          onLongPress: () => _showImageMenu(context, fullUrl),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220, maxHeight: 320),
              child: CachedNetworkImage(
                imageUrl: fullUrl,
                fit: BoxFit.contain,
                placeholder: (_, __) => Container(
                  width: 200,
                  height: 120,
                  color: Colors.black26,
                  child: const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00d4ff)),
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 200,
                  height: 100,
                  color: Colors.black26,
                  child: const Icon(Icons.broken_image, color: Color(0xFF94a3b8)),
                ),
              ),
            ),
          ),
        );
      case 'file':
        return _fileCard(textColor, context);
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

  Widget _fileCard(Color textColor, BuildContext context) {
    Map<String, dynamic>? meta;
    try {
      final raw = jsonDecode(message.content ?? '');
      if (raw is Map) meta = Map<String, dynamic>.from(raw);
    } catch (_) {}
    if (meta == null || (meta['path'] ?? '').toString().isEmpty) {
      return Text('文件消息', style: TextStyle(color: textColor));
    }
    final name = (meta['name'] ?? meta['path']).toString();
    final size = (meta['size'] is num) ? (meta['size'] as num).toInt() : 0;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final (icon, iconBg) = _fileVisual(ext);

    return GestureDetector(
      onTap: () => onFileTap?.call(message),
      child: Container(
        width: 230,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: textColor.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: textColor.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${ext.isEmpty ? 'FILE' : ext.toUpperCase()} · ${_formatSize(size)} · 点击下载',
                    style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  (IconData, Color) _fileVisual(String ext) {
    switch (ext) {
      case 'doc':
      case 'docx':
        return (Icons.description_outlined, const Color(0xFF2B579A));
      case 'xls':
      case 'xlsx':
      case 'csv':
        return (Icons.table_chart_outlined, const Color(0xFF217346));
      case 'ppt':
      case 'pptx':
        return (Icons.slideshow_outlined, const Color(0xFFD24726));
      case 'pdf':
        return (Icons.picture_as_pdf_outlined, const Color(0xFFD93025));
      case 'dwg':
      case 'dxf':
        return (Icons.architecture_outlined, const Color(0xFF0E7490));
      case 'txt':
      case 'md':
        return (Icons.article_outlined, const Color(0xFF0F766E));
      case 'zip':
      case 'rar':
      case '7z':
        return (Icons.folder_zip_outlined, const Color(0xFF64748B));
      default:
        return (Icons.insert_drive_file_outlined, const Color(0xFF0EA5E9));
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  String _formatTime(String createdAt) {
    if (createdAt.isEmpty) return '';
    // 简化处理：取 HH:mm:ss 部分
    final parts = createdAt.split(' ');
    if (parts.length >= 2) return parts[1].substring(0, 5);
    return createdAt;
  }
}
