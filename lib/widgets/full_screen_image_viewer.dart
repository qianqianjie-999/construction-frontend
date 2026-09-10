import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 全屏图片查看器：
/// - 横图点开**自动强制横屏满屏**，竖图保持竖屏
///   （App 显式 setRequestedOrientation，系统旋转锁定也生效）
/// - 右上角按钮可手动切换 横屏/竖屏
/// - 退出自动恢复竖屏，主界面保持竖屏习惯
/// - 双指缩放 1x~5x；点按关闭；长按/下载按钮可保存
class FullScreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final String? title;
  final VoidCallback? onSave;

  const FullScreenImageViewer({
    super.key,
    required this.imageUrl,
    this.title,
    this.onSave,
  });

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  /// null=初始（跟随图片自动判定），true=强制横屏，false=强制竖屏
  bool? _landscape;
  bool _decoded = false;

  static const _landscapeOrientations = [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];
  static const _portraitOrientations = [
    DeviceOrientation.portraitUp,
  ];

  @override
  void initState() {
    super.initState();
    // 默认竖屏（与主界面一致），图片解码后按宽高比自动决定
    SystemChrome.setPreferredOrientations(_portraitOrientations);
    _decodeAndAutoRotate();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(_portraitOrientations);
    super.dispose();
  }

  /// 预解码图片拿尺寸：横图（宽>高）自动强制横屏
  void _decodeAndAutoRotate() {
    final provider = CachedNetworkImageProvider(widget.imageUrl);
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      stream.removeListener(listener);
      if (!mounted) return;
      final image = info.image;
      final isLandscape = image.width > image.height;
      _decoded = true;
      if (isLandscape) {
        setState(() => _landscape = true);
        SystemChrome.setPreferredOrientations(_landscapeOrientations);
      } else {
        setState(() => _landscape = false);
      }
    }, onError: (_, __) {
      stream.removeListener(listener);
      if (mounted) setState(() => _landscape = false);
    });
    stream.addListener(listener);
  }

  Future<void> _toggle() async {
    final next = !(_landscape ?? false);
    setState(() => _landscape = next);
    await SystemChrome.setPreferredOrientations(
      next ? _landscapeOrientations : _portraitOrientations,
    );
  }

  @override
  Widget build(BuildContext context) {
    final landscape = _landscape ?? false;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: widget.title != null
            ? Text(widget.title!, style: const TextStyle(color: Colors.white))
            : null,
        actions: [
          if (_decoded)
            IconButton(
              icon: Icon(
                landscape ? Icons.stay_current_portrait : Icons.screen_rotation,
                color: const Color(0xFF00d4ff),
              ),
              tooltip: landscape ? '竖屏查看' : '横屏查看',
              onPressed: _toggle,
            ),
          if (widget.onSave != null)
            IconButton(
              icon: const Icon(Icons.download, color: Colors.white),
              tooltip: '保存到相册',
              onPressed: widget.onSave,
            ),
        ],
      ),
      body: Center(
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          onLongPress: widget.onSave,
          child: InteractiveViewer(
            minScale: 1.0,
            maxScale: 5.0,
            child: CachedNetworkImage(
              imageUrl: widget.imageUrl,
              fit: BoxFit.contain,
              placeholder: (_, __) => const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
              errorWidget: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image,
                    color: Colors.white54, size: 48),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
