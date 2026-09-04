import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import '../services/api_service.dart';

/// 文件下载进度对话框：下载完成后自动关闭并调用系统应用打开
/// （从 chat_screen.dart 拆出，无状态依赖，可独立复用）
class ChatDownloadDialog extends StatefulWidget {
  final String url;
  final String savePath;
  final String fileName;

  const ChatDownloadDialog({
    required this.url,
    required this.savePath,
    required this.fileName,
  });

  @override
  State<ChatDownloadDialog> createState() => _ChatDownloadDialogState();
}

class _ChatDownloadDialogState extends State<ChatDownloadDialog> {
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
