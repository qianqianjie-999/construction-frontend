import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:construction_app/models/project.dart';
import 'package:construction_app/models/construction_log.dart';
import 'package:construction_app/services/api_service.dart';
import 'package:construction_app/services/auth_service.dart';
import 'package:construction_app/services/image_save_service.dart';
import 'package:construction_app/services/pending_queue_service.dart';
import 'package:construction_app/screens/log_form_screen.dart';
import 'package:construction_app/widgets/full_screen_image_viewer.dart';
import 'package:intl/intl.dart';

class ProjectDetailScreen extends StatefulWidget {
  final Project project;
  const ProjectDetailScreen({super.key, required this.project});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  Future<List<ConstructionLog>>? _logsFuture;
  String _query = '';
  int _lastPendingLogCount = 0;

  // 离线缓存：断网时回落到上次成功同步的日志列表
  bool _offlineMode = false;
  DateTime? _cacheTime;

  /// 离线待发队列变化：刷新横幅；待发日志减少（刚补发成功）时刷新日志列表
  void _onPendingQueueChanged() {
    if (!mounted) return;
    final n =
        PendingQueueService().logItemsFor(widget.project.id).length;
    setState(() {});
    if (n < _lastPendingLogCount) {
      _refreshLogs();
    }
    _lastPendingLogCount = n;
  }

  /// 刷新日志列表：网络失败时回落本地缓存
  void _refreshLogs() {
    setState(() {
      _logsFuture = _loadLogsWithCache().whenComplete(() {
        if (mounted) setState(() {});
      });
    });
  }

  /// 网络成功 → 更新缓存并返回；失败 → 读缓存；无缓存则抛出原错误
  Future<List<ConstructionLog>> _loadLogsWithCache() async {
    try {
      final list =
          await ApiService().getLogsByProject(widget.project.id);
      await _saveLogCache(list);
      _offlineMode = false;
      return list;
    } catch (e) {
      final cached = await _readLogCache();
      if (cached == null) rethrow;
      _offlineMode = true;
      _cacheTime = cached.time;
      return cached.list;
    }
  }

  Future<void> _saveLogCache(List<ConstructionLog> list) async {
    try {
      final uid = AuthService().currentUser?.id ?? 0;
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
          'cache_logs_${uid}_${widget.project.id}', jsonEncode({
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'list': list.map((l) => l.toJson()).toList(),
      }));
    } catch (_) {
      // 缓存写失败不影响正常展示
    }
  }

  Future<({List<ConstructionLog> list, DateTime time})?> _readLogCache() async {
    try {
      final uid = AuthService().currentUser?.id ?? 0;
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('cache_logs_${uid}_${widget.project.id}');
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final list = (m['list'] as List)
          .map((e) =>
              ConstructionLog.fromJson(e as Map<String, dynamic>))
          .toList();
      final time =
          DateTime.fromMillisecondsSinceEpoch((m['savedAt'] as num).toInt());
      return (list: list, time: time);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _refreshLogs();
    _lastPendingLogCount =
        PendingQueueService().logItemsFor(widget.project.id).length;
    PendingQueueService().addListener(_onPendingQueueChanged);
    // 进页面时主动催一次队列（网络已恢复但没有事件触发的兜底）
    PendingQueueService().kick();
  }

  @override
  void dispose() {
    PendingQueueService().removeListener(_onPendingQueueChanged);
    super.dispose();
  }

  /// 离线模式横幅：正在展示缓存的施工日志
  Widget _buildOfflineBanner() {
    if (!_offlineMode) return const SizedBox.shrink();
    final t = _cacheTime;
    final timeStr = t != null
        ? '（${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} 同步）'
        : '';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x1AF59E0B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x66F59E0B)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 18, color: Color(0xFFF59E0B)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '当前离线，显示缓存的施工日志$timeStr',
              style: const TextStyle(
                  color: Color(0xFFfbbf24),
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: _refreshLogs,
            child: const Text('重试',
                style: TextStyle(color: Color(0xFF00d4ff), fontSize: 13)),
          ),
        ],
      ),
    );
  }

  /// 离线待提交日志横幅
  Widget _buildPendingLogsBanner() {
    final items = PendingQueueService().logItemsFor(widget.project.id);
    if (items.isEmpty) return const SizedBox.shrink();
    final hasFailed = items.any((it) => it.status == 'failed');
    final fmt = DateFormat('MM-dd HH:mm');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: hasFailed
            ? const Color(0x1AEF4444)
            : const Color(0x1AF59E0B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasFailed
              ? const Color(0x66EF4444)
              : const Color(0x66F59E0B),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(hasFailed ? Icons.error_outline : Icons.cloud_off,
                  size: 18,
                  color: hasFailed
                      ? const Color(0xFFef4444)
                      : const Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${items.length} 条日志待提交（联网后自动发送）',
                  style: TextStyle(
                    color: hasFailed
                        ? const Color(0xFFfca5a5)
                        : const Color(0xFFfbbf24),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => PendingQueueService().kick(),
                child: const Text('立即发送',
                    style:
                        TextStyle(color: Color(0xFF00d4ff), fontSize: 13)),
              ),
            ],
          ),
          ...items.map((it) {
            final logData =
                (it.payload['log'] is Map) ? it.payload['log'] as Map : null;
            final dateStr = logData?['date']?.toString();
            final label = dateStr != null && dateStr.length >= 10
                ? '日志日期 ${dateStr.substring(0, 10)}'
                : '录入于 ${fmt.format(it.createdAt)}';
            final photoCount =
                ((it.payload['photos'] as List?)?.length ?? 0) +
                    ((it.payload['certificates'] as List?)?.length ?? 0);
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(
                    it.status == 'sending'
                        ? Icons.sync
                        : it.status == 'failed'
                            ? Icons.error
                            : Icons.schedule,
                    size: 14,
                    color: it.status == 'failed'
                        ? const Color(0xFFef4444)
                        : const Color(0xFF94a3b8),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      it.status == 'failed'
                          ? '$label · 照片 $photoCount 张 · 失败：${it.failReason ?? '网络错误'}'
                          : '$label · 照片 $photoCount 张 · '
                              '${it.status == 'sending' ? '提交中…' : '待联网提交'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFFcbd5e1), fontSize: 12),
                    ),
                  ),
                  if (it.status == 'failed')
                    GestureDetector(
                      onTap: () => PendingQueueService().retry(it.id),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('重试',
                            style: TextStyle(
                                color: Color(0xFF00d4ff), fontSize: 12)),
                      ),
                    ),
                  GestureDetector(
                    onTap: () => _confirmRemovePendingLog(it.id),
                    child: const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.close,
                          size: 16, color: Color(0xFF94a3b8)),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 删除待提交日志前二次确认（删除后内容无法恢复）
  Future<void> _confirmRemovePendingLog(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a2332),
        title: const Text('放弃这条待提交日志？',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text('删除后该日志及照片将无法恢复。',
            style: TextStyle(color: Color(0xFF94a3b8), fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消',
                style: TextStyle(color: Color(0xFF94a3b8))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除',
                style: TextStyle(color: Color(0xFFef4444))),
          ),
        ],
      ),
    );
    if (ok == true) await PendingQueueService().remove(id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFF0B1220),
            surfaceTintColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0B1220), Color(0xFF151E2E)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20, right: 20, top: 50, bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00D4FF).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('项目详情', style: TextStyle(color: Color(0xFF00D4FF), fontSize: 11, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.location_on, color: Color(0xFF94a3b8), size: 14),
                            const SizedBox(width: 4),
                            Expanded(child: Text(widget.project.location.isEmpty ? '未填写地点' : widget.project.location, style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 12))),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.business, color: Color(0xFF94a3b8), size: 14),
                            const SizedBox(width: 4),
                            Expanded(child: Text(widget.project.company.isEmpty ? '未填写单位' : widget.project.company, style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 12))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                onPressed: () {
                  Navigator.pushNamed(context, '/log_form', arguments: widget.project).then((_) => _refreshLogs());
                },
                icon: const Icon(Icons.add_circle_outline, size: 24),
                tooltip: '录入日志',
              ),
              IconButton(
                onPressed: _exportLogs,
                icon: const Icon(Icons.download, size: 22),
                tooltip: '导出日志',
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                onChanged: (v) => setState(() => _query = v.trim()),
                style: const TextStyle(color: Color(0xFFf1f5f9), fontSize: 14),
                decoration: InputDecoration(
                  hintText: '搜索日期 / 天气 / 施工内容 / 记录',
                  hintStyle: const TextStyle(color: Color(0xFF64748b), fontSize: 14),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF64748b), size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFF1a2332),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF00d4ff), width: 1)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          // 离线模式横幅：正在展示缓存的施工日志
          SliverToBoxAdapter(child: _buildOfflineBanner()),
          // 离线待提交日志横幅（无待发项时为零高度）
          SliverToBoxAdapter(child: _buildPendingLogsBanner()),
          FutureBuilder<List<ConstructionLog>>(
            future: _logsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
              } else if (snapshot.hasError) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: const Color(0x10ef4444), shape: BoxShape.circle), child: const Icon(Icons.error_outline, size: 64, color: Color(0xFFef4444))),
                        const SizedBox(height: 24),
                        const Text('加载失败', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFf1f5f9))),
                        const SizedBox(height: 8),
                        Text(snapshot.error.toString(), style: const TextStyle(color: Color(0xFF64748b)), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                );
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: const Color(0x1000d4ff), shape: BoxShape.circle), child: const Icon(Icons.edit_calendar, size: 80, color: Color(0xFF00d4ff))),
                        const SizedBox(height: 24),
                        const Text('暂无日志记录', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFf1f5f9))),
                        const SizedBox(height: 8),
                        const Text('点击右上角 + 录入今日施工日志', style: TextStyle(fontSize: 16, color: Color(0xFF64748b))),
                      ],
                    ),
                  ),
                );
              } else {
                final all = snapshot.data!;
                final q = _query.toLowerCase();
                final logs = q.isEmpty
                    ? all
                    : all.where((l) =>
                        DateFormat('yyyy-MM-dd').format(l.date).contains(q) ||
                        DateFormat('yyyy年MM月dd日').format(l.date).contains(q) ||
                        DateFormat('MM月dd日').format(l.date).contains(q) ||
                        l.weather.toLowerCase().contains(q) ||
                        l.constructionPart.toLowerCase().contains(q) ||
                        l.constructionContent.toLowerCase().contains(q) ||
                        l.constructionRecord.toLowerCase().contains(q) ||
                        l.technicalSafetyRecord.toLowerCase().contains(q) ||
                        l.progress.toLowerCase().contains(q) ||
                        l.projectManager.toLowerCase().contains(q) ||
                        l.recorder.toLowerCase().contains(q)).toList();
                if (logs.isEmpty) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.search_off, size: 64, color: Color(0xFF64748b)),
                          const SizedBox(height: 16),
                          Text('没有匹配"$_query"的日志', style: const TextStyle(fontSize: 16, color: Color(0xFF94a3b8))),
                        ],
                      ),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final log = logs[index];
                        final weatherColor = _getWeatherColor(log.weather);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1a2332),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF2d3a4f)),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _showLogDetail(log),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(7),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [const Color(0xFF00d4ff).withOpacity(0.1), const Color(0xFF0099cc).withOpacity(0.1)]),
                                            borderRadius: BorderRadius.circular(9),
                                          ),
                                          child: const Icon(Icons.calendar_today, color: Color(0xFF00d4ff), size: 17),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(text: DateFormat('yyyy年MM月dd日').format(log.date), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFFf1f5f9))),
                                                TextSpan(text: '  ${DateFormat('EEEE', 'zh_CN').format(log.date)}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748b))),
                                              ],
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: weatherColor.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: weatherColor.withOpacity(0.3)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.cloud, size: 13, color: weatherColor),
                                              const SizedBox(width: 3),
                                              Text(log.weather.isEmpty ? '未知' : log.weather, style: TextStyle(color: weatherColor, fontWeight: FontWeight.w600, fontSize: 12)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (log.constructionContent.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(Icons.build, size: 13, color: Color(0xFF94a3b8)),
                                          const SizedBox(width: 5),
                                          Expanded(child: Text(log.constructionContent, style: const TextStyle(color: Color(0xFFf1f5f9), fontSize: 13, height: 1.35), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                        ],
                                      ),
                                    ],
                                    if (log.constructionRecord.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.people, size: 13, color: Color(0xFF94a3b8)),
                                          const SizedBox(width: 5),
                                          Expanded(child: Text(log.constructionRecord, style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 12, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis)),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: logs.length,
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Color _getWeatherColor(String weather) {
    switch (weather) {
      case '晴': return Colors.orange;
      case '多云': return Colors.blueGrey;
      case '阴': return Colors.grey;
      case '小雨': return Colors.blue;
      case '中雨': return Colors.blue;
      case '大雨': return Colors.blue;
      case '雪': return Colors.lightBlue;
      default: return const Color(0xFF2196F3);
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1a2332),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.redAccent, size: 28),
            SizedBox(width: 8),
            Text('删除项目', style: TextStyle(color: Color(0xFFf1f5f9))),
          ],
        ),
        content: Text(
          '确认删除项目「${widget.project.name}」？\n所有日志、照片、聊天记录将一并删除，此操作不可恢复！',
          style: const TextStyle(color: Color(0xFF94a3b8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Color(0xFF94a3b8))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _doDelete();
            },
            child: const Text('删除', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _doDelete() async {
    try {
      await ApiService().deleteProject(widget.project.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('项目已删除'), backgroundColor: Color(0xFF4CAF50)),
      );
      // 返回项目列表并刷新
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$e'), backgroundColor: const Color(0xFFef4444)),
      );
    }
  }

  void _exportLogs() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a2332),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(leading: const Icon(Icons.picture_as_pdf, color: Color(0xFFef4444)), title: const Text('导出为 PDF', style: TextStyle(color: Color(0xFFf1f5f9))), onTap: () { Navigator.pop(context); _exportLogsInFormat('pdf'); }),
            ListTile(leading: const Icon(Icons.table_chart, color: Color(0xFF4CAF50)), title: const Text('导出为 Excel', style: TextStyle(color: Color(0xFFf1f5f9))), onTap: () { Navigator.pop(context); _exportLogsInFormat('excel'); }),
          ],
        ),
      ),
    );
  }

  Future<void> _exportLogsInFormat(String format) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('正在导出日志...', style: TextStyle(color: Color(0xFFf1f5f9))), backgroundColor: Color(0xFF1a2332), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
      await ApiService().exportLogs(widget.project.id, format);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('日志导出成功，格式：$format', style: const TextStyle(color: Color(0xFFf1f5f9))), backgroundColor: const Color(0xFF4CAF50), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败：$e', style: const TextStyle(color: Color(0xFFf1f5f9))), backgroundColor: const Color(0xFFef4444), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
    }
  }

  void _showLogDetail(ConstructionLog log) {
    final weatherColor = _getWeatherColor(log.weather);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Color(0xFF1a2332),
          borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12), decoration: BoxDecoration(color: Color(0xFF2d3a4f), borderRadius: BorderRadius.circular(2))),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Center(child: Column(children: [
                    const Text('施工日志', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFf1f5f9))),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [weatherColor.withOpacity(0.1), weatherColor.withOpacity(0.05)]),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('${log.dateStr} ${log.weekdayStr}', style: TextStyle(fontSize: 15, color: weatherColor, fontWeight: FontWeight.w600)),
                    ),
                  ])),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LogFormScreen(project: widget.project, editLog: log),
                          ),
                        ).then((_) => _refreshLogs());
                      },
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('编辑'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00d4ff),
                        foregroundColor: const Color(0xFF0a0f1a),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [const Color(0xFF00d4ff).withOpacity(0.08), const Color(0xFF0099cc).withOpacity(0.04)]),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildDetailStat('天气', log.weather.isEmpty ? '-' : log.weather, Icons.cloud, weatherColor),
                            _buildDetailStat('气温', log.temperature.isEmpty ? '-' : log.temperature, Icons.thermostat, Colors.orange),
                            _buildDetailStat('风力', log.windForce.isEmpty ? '-' : log.windForce, Icons.air, Colors.teal),
                            _buildDetailStat('风向', log.windDirection.isEmpty ? '-' : log.windDirection, Icons.explore, Colors.cyan),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildSection('工程信息', Icons.engineering, const Color(0xFFFF9800), [
                    _buildDetailRow('当日工程施工部位', log.constructionPart),
                    _buildDetailRow('当日工程施工内容', log.constructionContent),
                    _buildDetailRow('当日工程形象进度', log.progress),
                  ]),
                  const SizedBox(height: 20),
                  _buildSection('记录详情', Icons.description, const Color(0xFF10B981), [
                    _buildDetailRow('施工情况记录', log.constructionRecord),
                    _buildDetailRow('技术质量安全工作记录', log.technicalSafetyRecord),
                    _buildDetailRow('材料进场检(试)验情况', log.materialRecord),
                  ]),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Color(0xFF111827), borderRadius: BorderRadius.circular(16), border: Border.all(color: Color(0xFF2d3a4f))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildPersonInfo('工程负责人', log.projectManager),
                        Container(height: 40, width: 1, color: Color(0xFF2d3a4f)),
                        _buildPersonInfo('记录人', log.recorder),
                      ],
                    ),
                  ),
                  if (log.photos.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _buildSection('现场照片', Icons.photo_library, const Color(0xFF00d4ff), [
                      _buildPhotosGrid(log.photos),
                    ]),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotosGrid(List<LogPhoto> photos) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final photo = photos[index];
        return GestureDetector(
          onTap: () => _showFullImage(photo.fullUrl),
          onLongPress: () => _saveImage(photo.fullUrl),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              photo.fullUrl,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return Container(
                  color: const Color(0xFF0a0f1a),
                  child: Center(
                    child: CircularProgressIndicator(
                      value: progress.cumulativeBytesLoaded / (progress.expectedTotalBytes ?? 1),
                      color: const Color(0xFF00d4ff),
                    ),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFF0a0f1a),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image, color: Color(0xFF94a3b8), size: 32),
                    SizedBox(height: 4),
                    Text('加载失败', style: TextStyle(color: Color(0xFF64748b), fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showFullImage(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullScreenImageViewer(
          imageUrl: url,
          title: '照片预览',
          onSave: () => _saveImage(url),
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

  Widget _buildDetailStat(String label, String value, IconData icon, Color color) {
    return Column(children: [
      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 22)),
      const SizedBox(height: 8),
      Text(label, style: TextStyle(fontSize: 12, color: Color(0xFF94a3b8))),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFf1f5f9))),
    ]);
  }

  Widget _buildSection(String title, IconData icon, Color color, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 20)),
        const SizedBox(width: 12),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFf1f5f9))),
      ]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Color(0xFF1a2332), borderRadius: BorderRadius.circular(16), border: Border.all(color: Color(0xFF2d3a4f))),
        child: Column(children: children),
      ),
    ]);
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 140, child: Text(label, style: TextStyle(fontSize: 14, color: Color(0xFF94a3b8)))),
        const SizedBox(width: 12),
        Expanded(child: Text(value.isEmpty ? '-' : value, style: const TextStyle(fontSize: 14, color: Color(0xFFf1f5f9)))),
      ]),
    );
  }

  Widget _buildPersonInfo(String label, String value) {
    return Column(children: [
      Text(label, style: TextStyle(fontSize: 12, color: Color(0xFF94a3b8))),
      const SizedBox(height: 4),
      Text(value.isEmpty ? '-' : value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFf1f5f9))),
    ]);
  }
}