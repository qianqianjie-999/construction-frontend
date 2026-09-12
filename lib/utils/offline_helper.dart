import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// 设备当前是否有物理网络（WiFi / 移动网络等）。
/// 只代表设备已联网，不代表能连通业务服务器（弱网、内网不通等场景仍会请求失败）。
Future<bool> isDeviceOnline() async {
  final results = await Connectivity().checkConnectivity();
  return results.any((r) => r != ConnectivityResult.none);
}

/// 网络重试期间询问用户是否立刻进入离线模式（看本地缓存）。
/// 返回 true = 进入离线模式；false / 关闭弹窗 = 继续等待网络重试。
Future<bool> showOfflineModeDialog(
  BuildContext context, {
  String title = '当前网络连接不稳定',
}) async {
  final enter = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1a2332),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      icon: const Icon(Icons.cloud_off, color: Color(0xFFF59E0B), size: 38),
      title: Text(title,
          style: const TextStyle(color: Colors.white, fontSize: 17),
          textAlign: TextAlign.center),
      content: const Text(
        '可以直接进入离线模式查看本地缓存，联网后数据会自动同步，待发送的消息和日志也会自动补发。',
        style: TextStyle(color: Color(0xFF94a3b8), fontSize: 14),
      ),
      actionsPadding: const EdgeInsets.only(right: 12, bottom: 6),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('继续等待',
              style: TextStyle(color: Color(0xFF94a3b8))),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF00d4ff),
            foregroundColor: const Color(0xFF0a0f1a),
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('进入离线模式',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
  return enter ?? false;
}
