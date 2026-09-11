import 'dart:io';

import 'package:flutter/material.dart';

import '../services/pending_queue_service.dart';

/// 离线待发的聊天消息气泡（仅显示在自己一侧的列表尾部）。
/// pending 等待网络 / sending 发送中 / failed 发送失败（可重试或删除）。
class PendingMessageBubble extends StatelessWidget {
  final PendingItem item;
  final Future<void> Function(String id) onRetry;
  final Future<void> Function(String id) onRemove;

  const PendingMessageBubble({
    super.key,
    required this.item,
    required this.onRetry,
    required this.onRemove,
  });

  static const _bg = Color(0xCC0E7490); // 比正常气泡暗一些，表示"尚未发出"
  static const _fg = Color(0xE6F1F5F9);

  String get _hhmm {
    final t = item.createdAt;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  String _fileSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  Future<void> _showActions(BuildContext context) async {
    if (item.isSending) return; // 发送中不允许操作
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a2332),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Wrap(
          children: [
            if (item.isFailed)
              ListTile(
                leading: const Icon(Icons.refresh, color: Color(0xFF00d4ff)),
                title: const Text('立即重试',
                    style: TextStyle(color: Color(0xFFf1f5f9))),
                subtitle: Text(item.failReason ?? '',
                    style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 12)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  onRetry(item.id);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFef4444)),
              title: Text(item.isFailed ? '删除（不再发送）' : '取消发送',
                  style: const TextStyle(color: Color(0xFFef4444))),
              onTap: () {
                Navigator.pop(sheetCtx);
                onRemove(item.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusIcon() {
    if (item.isSending) {
      return const SizedBox(
        width: 13,
        height: 13,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
      );
    }
    if (item.isFailed) {
      return const Icon(Icons.error, size: 15, color: Color(0xFFef4444));
    }
    return const Icon(Icons.schedule, size: 14, color: Colors.white70);
  }

  String get _statusText {
    if (item.isSending) return '发送中…';
    if (item.isFailed) return '发送失败，点击重试';
    return '待发送（联网后自动发出）';
  }

  Widget _content(BuildContext context) {
    switch (item.type) {
      case PendingType.chatImage:
        return FutureBuilder<String>(
          future: PendingQueueService().localAbsolutePath(item),
          builder: (context, snap) {
            final path = snap.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: path != null && File(path).existsSync()
                      ? Image.file(File(path),
                          width: 200, height: 150, fit: BoxFit.cover)
                      : const SizedBox(
                          width: 200,
                          height: 150,
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: Colors.white70))),
                ),
                _footer(),
              ],
            );
          },
        );

      case PendingType.chatFile:
        final name = item.payload['name']?.toString() ?? '文件';
        final size = (item.payload['size'] as num?)?.toInt() ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.insert_drive_file_outlined,
                    color: _fg, size: 30),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(color: _fg, fontSize: 14),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      Text(_fileSize(size),
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _footer(),
          ],
        );

      case PendingType.chatLocation:
        final text = item.payload['text']?.toString() ?? '';
        final lat = item.payload['lat'];
        final lng = item.payload['lng'];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_on, color: _fg, size: 22),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(text.isEmpty ? '位置消息' : text,
                      style: const TextStyle(color: _fg, fontSize: 14),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            if (lat != null && lng != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 30),
                child: Text('$lat, $lng',
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 11)),
              ),
            const SizedBox(height: 6),
            _footer(),
          ],
        );

      case PendingType.chatText:
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.payload['text']?.toString() ?? '',
              style: const TextStyle(color: _fg, fontSize: 15),
            ),
            const SizedBox(height: 4),
            _footer(),
          ],
        );
    }
  }

  Widget _footer() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_statusText,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(width: 5),
        _statusIcon(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => _showActions(context),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              padding: EdgeInsets.all(item.type == PendingType.chatImage ? 3 : 10),
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(2),
                ),
                border: item.isFailed
                    ? Border.all(color: const Color(0xFFef4444), width: 1.2)
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _content(context),
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 2),
                    child: Text(_hhmm,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 10)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
