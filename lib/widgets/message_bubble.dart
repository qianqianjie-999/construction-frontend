import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../services/chat_service.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';

/// 聊天消息气泡
class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onLogCardTap;
  final ValueChanged<String>? onImageTap;
  final ValueChanged<String>? onImageLongPress;
  final ValueChanged<ChatMessage>? onFileTap;
  final ValueChanged<int>? onRecall; // 撤回回调
  final bool highlight; // 搜索结果定位时高亮边框

  // 多选转发模式
  final bool selectionMode; // 是否处于多选模式
  final bool selected; // 本条是否被选中
  final ValueChanged<int>? onToggleSelect; // 点击切换选中
  final VoidCallback? onEnterMultiSelect; // 长按菜单选"多选"后进入多选模式

  const MessageBubble({
    super.key,
    required this.message,
    this.onLogCardTap,
    this.onImageTap,
    this.onImageLongPress,
    this.onFileTap,
    this.onRecall,
    this.highlight = false,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelect,
    this.onEnterMultiSelect,
  });

  bool get _isMine {
    final me = AuthService().currentUser;
    return me != null && me.id == message.userId;
  }

  /// 是否可撤回：自己的消息且发送不超过 2 分钟（与后端普通用户时限一致，
  /// 超时不再显示撤回入口，避免点了才报错）
  bool get _canRecall {
    if (!_isMine || onRecall == null || message.id == null) return false;
    final dt = DateTime.tryParse(message.createdAt);
    if (dt == null) return true; // 时间解析失败不拦截，交由后端判定
    return DateTime.now().difference(dt).inSeconds < 120;
  }

  @override
  Widget build(BuildContext context) {
    final isMine = _isMine;
    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleColor =
        isMine ? const Color(0xFF00d4ff) : const Color(0xFF1a2332);
    final textColor =
        isMine ? const Color(0xFF0a0f1a) : const Color(0xFFf1f5f9);

    // 已撤回消息：不渲染（列表层已过滤，这里仅作兜底，零占位）
    if (message.recalled) {
      return const SizedBox.shrink();
    }

    final row = Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (selectionMode && !isMine) _selectCheck(),
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
                      style: const TextStyle(
                          color: Color(0xFF94a3b8), fontSize: 12),
                    ),
                  ),
                Container(
                  constraints: const BoxConstraints(maxWidth: 280),
                  // 图片消息边距收窄（图片几乎撑满气泡），文本等保持 10
                  padding: EdgeInsets.all(
                      message.contentType == 'image' ? 3 : 10),
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
                    style:
                        const TextStyle(color: Color(0xFF64748b), fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
          if (isMine) _avatar(),
          if (selectionMode && isMine) _selectCheck(),
        ],
      ),
    );

    // 多选模式：整条消息点击切换选中，内部交互（导航/预览/长按菜单）全部禁用
    // 必须 opaque：IgnorePointer 屏蔽子组件后，deferToChild 会导致外层也收不到点击
    if (selectionMode) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap:
            message.id == null ? null : () => onToggleSelect?.call(message.id!),
        child: IgnorePointer(ignoring: true, child: row),
      );
    }
    return GestureDetector(
      onLongPress: () => _showBubbleMenu(context),
      child: row,
    );
  }

  /// 多选模式下的选中圆圈
  Widget _selectCheck() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Icon(
        selected ? Icons.check_circle : Icons.radio_button_unchecked,
        color: selected ? const Color(0xFF00d4ff) : const Color(0xFF64748b),
        size: 22,
      ),
    );
  }

  void _showImageMenu(BuildContext context, String url) {
    final actions = <Widget>[];
    // 多选（批量转发）
    if (message.id != null && onEnterMultiSelect != null) {
      actions.add(ListTile(
        leading: const Icon(Icons.checklist, color: Color(0xFF00d4ff)),
        title: const Text('多选', style: TextStyle(color: Color(0xFFf1f5f9))),
        onTap: () {
          Navigator.pop(context);
          onEnterMultiSelect!.call();
        },
      ));
    }
    // 转发图片（下载到临时目录后调系统分享面板）
    actions.add(ListTile(
      leading: const Icon(Icons.forward, color: Color(0xFF00d4ff)),
      title: const Text('转发给朋友', style: TextStyle(color: Color(0xFFf1f5f9))),
      onTap: () {
        Navigator.pop(context);
        _shareImage(context, url);
      },
    ));
    // 自己的消息且发送不超过 2 分钟 → 加撤回选项
    if (_canRecall) {
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
        content: const Text('确定要撤回这条消息吗？',
            style: TextStyle(color: Color(0xFF94a3b8))),
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
            child: const Text('撤回',
                style: TextStyle(
                    color: Color(0xFFef4444), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// 长按消息气泡的通用操作菜单（转发 / 撤回）
  /// 图片长按走自己的菜单、点位点按走导航菜单，这里主要覆盖文本/文件/点位长按
  void _showBubbleMenu(BuildContext context) {
    final actions = <Widget>[];

    if (message.id != null && onEnterMultiSelect != null) {
      actions.add(ListTile(
        leading: const Icon(Icons.checklist, color: Color(0xFF00d4ff)),
        title: const Text('多选', style: TextStyle(color: Color(0xFFf1f5f9))),
        onTap: () {
          Navigator.pop(context);
          onEnterMultiSelect!.call();
        },
      ));
    }

    if (message.contentType == 'text' && (message.content ?? '').isNotEmpty) {
      actions.add(ListTile(
        leading: const Icon(Icons.forward, color: Color(0xFF00d4ff)),
        title: const Text('转发给朋友', style: TextStyle(color: Color(0xFFf1f5f9))),
        onTap: () {
          Navigator.pop(context);
          Share.share(message.content!);
        },
      ));
    } else if (message.contentType == 'file') {
      actions.add(ListTile(
        leading: const Icon(Icons.forward, color: Color(0xFF00d4ff)),
        title: const Text('转发文件', style: TextStyle(color: Color(0xFFf1f5f9))),
        onTap: () {
          Navigator.pop(context);
          _shareFile(context);
        },
      ));
    } else if (message.contentType == 'location') {
      actions.add(ListTile(
        leading: const Icon(Icons.share, color: Color(0xFF00d4ff)),
        title: const Text('分享位置（微信/短信等）',
            style: TextStyle(color: Color(0xFFf1f5f9))),
        onTap: () {
          Navigator.pop(context);
          final loc = _parseLocation();
          if (loc != null)
            _shareLocation(loc.lat, loc.lng, loc.title, loc.address);
        },
      ));
    }

    if (_canRecall) {
      actions.add(ListTile(
        leading: const Icon(Icons.undo, color: Color(0xFFef4444)),
        title: const Text('撤回消息', style: TextStyle(color: Color(0xFFef4444))),
        onTap: () {
          Navigator.pop(context);
          _showRecallMenu(context);
        },
      ));
    }

    if (actions.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a2332),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: actions),
      ),
    );
  }

  /// 解析点位消息内容，返回 {lat, lng, title, address}；无效返回 null
  ({double lat, double lng, String title, String address})? _parseLocation() {
    try {
      final raw = jsonDecode(message.content ?? '');
      if (raw is! Map) return null;
      final lat = (raw['lat'] is num) ? (raw['lat'] as num).toDouble() : null;
      final lng = (raw['lng'] is num) ? (raw['lng'] as num).toDouble() : null;
      if (lat == null || lng == null) return null;
      final text = (raw['text'] ?? '').toString();
      final address = (raw['address'] ?? '').toString();
      final title =
          text.isNotEmpty ? text : (address.isNotEmpty ? address : '位置共享');
      return (lat: lat, lng: lng, title: title, address: address);
    } catch (_) {
      return null;
    }
  }

  /// 转发文件：先下载到临时目录（dio 全局带登录鉴权），再调系统分享
  Future<void> _shareFile(BuildContext context) async {
    Map<String, dynamic>? meta;
    try {
      final raw = jsonDecode(message.content ?? '');
      if (raw is Map) meta = Map<String, dynamic>.from(raw);
    } catch (_) {}
    final path = (meta?['path'] ?? '').toString();
    final name = (meta?['name'] ?? path).toString();
    if (path.isEmpty) return;
    await _downloadAndShare(
        context, ChatService().fileUrl(path, name: name), name);
  }

  /// 转发图片：下载到临时目录后调系统分享
  Future<void> _shareImage(BuildContext context, String url) async {
    final segments = Uri.tryParse(url)?.pathSegments ?? const [];
    final fileName = segments.isNotEmpty ? segments.last : 'shared_image.jpg';
    await _downloadAndShare(context, url, fileName);
  }

  /// 下载远程文件到临时目录并调起系统分享面板
  Future<void> _downloadAndShare(
      BuildContext context, String url, String fileName) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await getTemporaryDirectory();
      final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final savePath =
          '${dir.path}/share_${DateTime.now().millisecondsSinceEpoch}_$safeName';
      messenger.showSnackBar(const SnackBar(
        content: Text('正在准备文件，请稍候…'),
        duration: Duration(seconds: 1),
      ));
      await ApiService.instance.dio.download(url, savePath);
      await Share.shareXFiles([XFile(savePath)]);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('分享失败：$e'),
        backgroundColor: const Color(0xFFef4444),
      ));
    }
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
          style: const TextStyle(
              color: Color(0xFF00d4ff), fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _content(Color textColor, BuildContext context) {
    switch (message.contentType) {
      case 'image':
        final url = message.content ?? '';
        if (url.isEmpty) return const SizedBox.shrink();
        final isAbsolute = url.startsWith('http');
        final fullUrl = Uri.parse(
          isAbsolute ? url : ChatService().imageUrl(url),
        ).toString();
        // 气泡只加载 400px 缩略图（省 ~70% 流量），点开全屏/保存/转发才用原图
        final thumbUrl = isAbsolute ? fullUrl : ChatService().thumbUrl(url);
        return GestureDetector(
          onTap: () => onImageTap?.call(fullUrl),
          onLongPress: () => _showImageMenu(context, fullUrl),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220, maxHeight: 320),
              child: CachedNetworkImage(
                imageUrl: thumbUrl,
                fit: BoxFit.contain,
                // 缩略图长边 400px，memCacheWidth 作为解码上限保险；
                // 点开全屏预览走独立页面加载原图，清晰度不受影响。
                memCacheWidth: 600,
                placeholder: (_, __) => Container(
                  width: 200,
                  height: 120,
                  color: Colors.black26,
                  child: const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF00d4ff)),
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) =>
                    // 兜底：旧版后端没有 thumb 路由（404）时回退加载原图
                    CachedNetworkImage(
                  imageUrl: fullUrl,
                  fit: BoxFit.contain,
                  memCacheWidth: 600,
                  placeholder: (_, __) => Container(
                    width: 200,
                    height: 120,
                    color: Colors.black26,
                    child: const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF00d4ff)),
                      ),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    width: 200,
                    height: 100,
                    color: Colors.black26,
                    child: const Icon(Icons.broken_image,
                        color: Color(0xFF94a3b8)),
                  ),
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
                const Icon(Icons.description,
                    size: 32, color: Color(0xFF00d4ff)),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('施工日志',
                        style: TextStyle(
                            color: textColor, fontWeight: FontWeight.bold)),
                    Text('点击查看',
                        style: TextStyle(
                            color: textColor.withOpacity(0.7), fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        );
      case 'location':
        return _locationCard(textColor, context);
      case 'text':
      default:
        return Text(
          message.content ?? '',
          style: TextStyle(color: textColor, fontSize: 14, height: 1.4),
        );
    }
  }

  Widget _locationCard(Color textColor, BuildContext context) {
    Map<String, dynamic>? loc;
    try {
      final raw = jsonDecode(message.content ?? '');
      if (raw is Map) loc = Map<String, dynamic>.from(raw);
    } catch (_) {}
    final lat = (loc?['lat'] is num) ? (loc!['lat'] as num).toDouble() : null;
    final lng = (loc?['lng'] is num) ? (loc!['lng'] as num).toDouble() : null;
    if (lat == null || lng == null) {
      return Text('位置消息', style: TextStyle(color: textColor));
    }
    final text = (loc?['text'] ?? '').toString();
    final address = (loc?['address'] ?? '').toString();
    final title =
        text.isNotEmpty ? text : (address.isNotEmpty ? address : '位置共享');
    final pinColor =
        _isMine ? const Color(0xFF0a0f1a) : const Color(0xFF00d4ff);

    return GestureDetector(
      onTap: () => _showNavigationMenu(context, lat, lng, title, address),
      child: SizedBox(
        width: 240,
        child: Row(
          children: [
            // 小地图缩略块：网格 + 定位图标
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 48,
                height: 48,
                color: textColor.withOpacity(0.08),
                child: CustomPaint(
                  painter:
                      _MapGridPainter(textColor.withOpacity(0.12), step: 12),
                  child: Center(
                    child: Icon(Icons.location_on, color: pinColor, size: 24),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)} · 点击导航',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: textColor.withOpacity(0.6), fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNavigationMenu(BuildContext context, double lat, double lng,
      String title, String address) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a2332),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share, color: Color(0xFF00d4ff)),
              title: const Text('分享位置（微信/短信等）',
                  style: TextStyle(color: Color(0xFFf1f5f9))),
              onTap: () {
                Navigator.pop(ctx);
                _shareLocation(lat, lng, title, address);
              },
            ),
            ListTile(
              leading: const Icon(Icons.map, color: Color(0xFF00d4ff)),
              title: const Text('查看位置',
                  style: TextStyle(color: Color(0xFFf1f5f9))),
              onTap: () {
                Navigator.pop(ctx);
                _launchAmap(
                    'https://uri.amap.com/marker?position=$lng,$lat&coordinate=gaode&callnative=1');
              },
            ),
            ListTile(
              leading: const Icon(Icons.navigation, color: Color(0xFF00d4ff)),
              title: const Text('开始导航',
                  style: TextStyle(color: Color(0xFFf1f5f9))),
              onTap: () {
                Navigator.pop(ctx);
                _launchAmap(
                    'https://uri.amap.com/navigation?to=$lng,$lat&coordinate=gaode&mode=car');
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 转发点位：文字 + 高德链接，外部人员在微信/短信里点开即可看位置、导航
  Future<void> _shareLocation(
      double lat, double lng, String title, String address) async {
    final mapUrl =
        'https://uri.amap.com/marker?position=$lng,$lat&coordinate=gaode&callnative=1';
    final buf = StringBuffer('【位置共享】$title\n');
    buf.writeln('坐标：${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}');
    if (address.isNotEmpty && address != title) buf.writeln('地址：$address');
    buf.write('点击查看位置/导航：$mapUrl');
    await Share.share(buf.toString(), subject: '位置共享：$title');
  }

  Future<void> _launchAmap(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('打开地图失败: $e');
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
                    style: TextStyle(
                        color: textColor.withOpacity(0.6), fontSize: 11),
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
    if (bytes >= 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  String _formatTime(String createdAt) {
    if (createdAt.isEmpty) return '';
    try {
      DateTime dt;
      if (createdAt.contains('T')) {
        dt = DateTime.parse(createdAt).toLocal();
      } else {
        final parts = createdAt.split(' ');
        if (parts.length < 2) return createdAt;
        dt = DateTime.parse('${parts[0]}T${parts[1]}').toLocal();
      }
      final now = DateTime.now();
      final isToday =
          dt.year == now.year && dt.month == now.month && dt.day == now.day;
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      if (isToday) return '$hh:$mm';
      return '${dt.month}/${dt.day} $hh:$mm';
    } catch (_) {
      final parts = createdAt.split(' ');
      if (parts.length >= 2) return parts[1].substring(0, 5);
      return createdAt;
    }
  }
}

/// 位置卡片"伪地图"网格背景
class _MapGridPainter extends CustomPainter {
  final Color lineColor;
  final double step;
  _MapGridPainter(this.lineColor, {this.step = 16.0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    for (double x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_MapGridPainter oldDelegate) =>
      oldDelegate.lineColor != lineColor || oldDelegate.step != step;
}
