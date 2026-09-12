import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:construction_app/models/project.dart';
import 'package:construction_app/services/api_service.dart';
import 'package:construction_app/services/auth_service.dart';
import 'package:construction_app/services/chat_service.dart';
import 'package:construction_app/services/pending_queue_service.dart';
import 'package:construction_app/utils/offline_helper.dart';
import 'package:construction_app/screens/chat_screen.dart';

class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key});

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  late Future<List<Project>> _projectsFuture;
  Map<int, int> _unread = {};
  String _query = '';
  int _retrying = 0; // 当前正在进行第几次重试（0 = 没有在重试）

  // 离线缓存：断网时回落到上次成功同步的项目列表
  bool _offlineMode = false;
  DateTime? _cacheTime;

  int _loadGen = 0; // 加载代际：进入离线模式后作废旧的在途网络请求结果
  bool _offlineAsked = false; // 本次加载周期内是否已经问过"进入离线模式"
  bool _loadDone = false; // 当前加载是否已结束（防止慢网询问窗与结果同时出现）
  Timer? _slowTimer; // 慢网倒计时：超时未返回就主动询问是否进离线
  StreamSubscription<RetryEvent>? _retrySub;

  @override
  void initState() {
    super.initState();
    _startLoad();
    _refreshUnread();
    // 监听全局网络重试事件，在 UI 上给可见反馈
    _retrySub = ApiService.instance.retryEvents.listen((event) {
      if (event.path == '/api/projects' || event.path == '/api/chat/unread') {
        if (!mounted) return;
        setState(() => _retrying = event.attempt);
        // 短暂显示 SnackBar 提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '网络不稳定(${event.reason})，第 ${event.attempt}/3 次重试…',
              style: const TextStyle(color: Color(0xFF00d4ff), fontSize: 13),
            ),
            backgroundColor: const Color(0xFF1a2332),
            duration: Duration(milliseconds: event.waitMs + 200),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _retrySub?.cancel();
    super.dispose();
  }

  /// 发起一次项目列表加载
  void _startLoad() {
    _offlineAsked = false;
    _loadDone = false;
    final gen = ++_loadGen;
    _slowTimer?.cancel();
    setState(() {
      _projectsFuture = _runLoad(gen).whenComplete(() {
        _loadDone = true;
        _slowTimer?.cancel();
        if (mounted && gen == _loadGen) setState(() {});
      });
    });
    // 不管 WiFi 还是 4G/5G：2.5 秒数据还没回来且本地有缓存，就主动询问，
    // 不必等满 8 秒连接超时 + 3 次重试
    _slowTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted && gen == _loadGen && !_loadDone) {
        _maybePromptOffline();
      }
    });
  }

  /// 刷新项目列表：网络失败时回落本地缓存
  void _refreshProjects() => _startLoad();

  Future<List<Project>> _runLoad(int gen) async {
    // 设备完全无网（飞行模式/无 WiFi/无流量）：一个请求都不发，直接读缓存秒进
    if (!await isDeviceOnline()) {
      final cached = await _readProjectCache();
      if (cached != null) {
        if (gen == _loadGen) {
          _offlineMode = true;
          _cacheTime = cached.time;
        }
        return cached.list;
      }
      // 没有缓存时继续走网络，让页面展示正常的错误+重试按钮
    }
    return _loadProjectsWithCache(gen);
  }

  /// 网络成功 → 更新缓存并返回；失败 → 读缓存（按登录用户隔离）；无缓存则抛出原错误
  Future<List<Project>> _loadProjectsWithCache(int gen) async {
    try {
      final list = await ApiService().getProjects();
      await _saveProjectCache(list);
      if (gen == _loadGen) _offlineMode = false;
      return list;
    } catch (e) {
      final cached = await _readProjectCache();
      if (cached == null) rethrow;
      if (gen == _loadGen) {
        _offlineMode = true;
        _cacheTime = cached.time;
      }
      return cached.list;
    }
  }

  /// 第 1 次重试时询问用户是否立刻进入离线模式（有缓存才问）
  Future<void> _maybePromptOffline() async {
    if (_offlineAsked || !mounted) return;
    final cached = await _readProjectCache();
    if (!mounted || cached == null) return;
    _offlineAsked = true;
    final enter = await showOfflineModeDialog(context);
    if (!mounted || !enter) return;
    _enterOffline(cached);
  }

  /// 立即切到缓存视图，并不再让在途的网络请求结果覆盖界面
  void _enterOffline(({List<Project> list, DateTime time}) cached) {
    _loadGen++;
    _offlineMode = true;
    _cacheTime = cached.time;
    setState(() => _projectsFuture = Future.value(cached.list));
  }

  Future<void> _saveProjectCache(List<Project> list) async {
    try {
      final uid = AuthService().currentUser?.id ?? 0;
      final sp = await SharedPreferences.getInstance();
      await sp.setString('cache_projects_$uid', jsonEncode({
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'list': list.map((p) => p.toJson()).toList(),
      }));
    } catch (_) {
      // 缓存写失败不影响正常展示
    }
  }

  Future<({List<Project> list, DateTime time})?> _readProjectCache() async {
    try {
      final uid = AuthService().currentUser?.id ?? 0;
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('cache_projects_$uid');
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final list = (m['list'] as List)
          .map((e) => Project.fromJson(e as Map<String, dynamic>))
          .toList();
      final time =
          DateTime.fromMillisecondsSinceEpoch((m['savedAt'] as num).toInt());
      return (list: list, time: time);
    } catch (_) {
      return null;
    }
  }

  Future<void> _refreshUnread() async {
    try {
      final m = await ChatService().unreadCount();
      setState(() => _unread = m);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 110,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFF1a2332),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Color(0xFF00d4ff)),
                onPressed: () {
                  _refreshProjects();
                  _refreshUnread();
                  setState(() {});
                },
              ),
              PopupMenuButton<String>(
                icon: CircleAvatar(
                  backgroundColor: const Color(0xFF00d4ff).withOpacity(0.2),
                  child: Text(
                    (AuthService().currentUser?.nickname ?? '?').characters.first,
                    style: const TextStyle(color: Color(0xFF00d4ff), fontWeight: FontWeight.bold),
                  ),
                ),
                color: const Color(0xFF1a2332),
                onSelected: (v) async {
                  if (v == 'logout') {
                    PendingQueueService().clearForUser();
                    await AuthService().logout();
                    if (!mounted) return;
                    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem<String>(
                    enabled: false,
                    child: Row(
                      children: [
                        const Icon(Icons.person, color: Color(0xFF00d4ff), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          AuthService().currentUser?.nickname ?? '',
                          style: const TextStyle(color: Color(0xFFf1f5f9)),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout, color: Color(0xFFef4444), size: 18),
                        SizedBox(width: 8),
                        Text('退出登录', style: TextStyle(color: Color(0xFFef4444))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                '工程现场管理',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFFf1f5f9)),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0a0f1a), Color(0xFF1a2332)],
                  ),
                ),
                child: const Stack(
                  children: [
                    Positioned(
                      top: 20,
                      right: -40,
                      width: 120,
                      height: 120,
                      child: CircleAvatar(
                        backgroundColor: Color(0x1000d4ff),
                        radius: 60,
                      ),
                    ),
                    Positioned(
                      top: 60,
                      right: 20,
                      width: 60,
                      height: 60,
                      child: CircleAvatar(
                        backgroundColor: Color(0x2000d4ff),
                        radius: 30,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 离线模式横幅：正在展示缓存的项目列表
          if (_offlineMode)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
                        '当前离线，显示缓存的项目列表${_cacheTime != null ? '（${_cacheTime!.month.toString().padLeft(2, '0')}-${_cacheTime!.day.toString().padLeft(2, '0')} ${_cacheTime!.hour.toString().padLeft(2, '0')}:${_cacheTime!.minute.toString().padLeft(2, '0')} 同步）' : ''}',
                        style: const TextStyle(color: Color(0xFFfbbf24), fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _refreshProjects,
                      child: const Text('重试', style: TextStyle(color: Color(0xFF00d4ff), fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                onChanged: (v) => setState(() => _query = v.trim()),
                style: const TextStyle(color: Color(0xFFf1f5f9), fontSize: 14),
                decoration: InputDecoration(
                  hintText: '搜索项目 / 地点 / 单位 / 负责人',
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
          FutureBuilder<List<Project>>(
            future: _projectsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: Color(0xFF00d4ff)),
                        const SizedBox(height: 16),
                        Text(
                          _retrying > 0
                              ? '网络不稳定，正在第 $_retrying/3 次重试…'
                              : '正在加载项目列表…',
                          style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                );
              } else if (snapshot.hasError) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(color: const Color(0x10ef4444), shape: BoxShape.circle),
                          child: const Icon(Icons.error_outline, size: 64, color: Color(0xFFef4444)),
                        ),
                        const SizedBox(height: 24),
                        const Text('加载失败', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFf1f5f9))),
                        const SizedBox(height: 8),
                        Text(snapshot.error.toString(), style: const TextStyle(color: Color(0xFF64748b)), textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _refreshProjects,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试'),
                        ),
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
                        Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: const Color(0x1000d4ff), shape: BoxShape.circle), child: const Icon(Icons.folder_open, size: 80, color: Color(0xFF00d4ff))),
                        const SizedBox(height: 24),
                        const Text('暂无项目', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFf1f5f9))),
                        const SizedBox(height: 8),
                        const Text('请在管理后台创建项目', style: TextStyle(fontSize: 16, color: Color(0xFF64748b))),
                      ],
                    ),
                  ),
                );
              } else {
                final all = snapshot.data!;
                final q = _query.toLowerCase();
                final projects = q.isEmpty
                    ? all
                    : all.where((p) =>
                        p.name.toLowerCase().contains(q) ||
                        p.location.toLowerCase().contains(q) ||
                        p.company.toLowerCase().contains(q) ||
                        p.manager.toLowerCase().contains(q)).toList();
                if (projects.isEmpty) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.search_off, size: 64, color: Color(0xFF64748b)),
                          const SizedBox(height: 16),
                          Text('没有匹配"$_query"的项目', style: const TextStyle(fontSize: 16, color: Color(0xFF94a3b8))),
                        ],
                      ),
                    ),
                  );
                }
                final cardColors = [
                  [const Color(0xFF00d4ff), const Color(0xFF0099cc)],
                  [const Color(0xFF10b981), const Color(0xFF059669)],
                  [const Color(0xFFf59e0b), const Color(0xFFd97706)],
                  [const Color(0xFF8b5cf6), const Color(0xFF7c3aed)],
                  [const Color(0xFFec4899), const Color(0xFFdb2777)],
                ];
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final project = projects[index];
                        final colorPair = cardColors[index % cardColors.length];
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
                              onTap: () => Navigator.pushNamed(context, '/project_detail', arguments: project),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 42, height: 42,
                                      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colorPair), borderRadius: BorderRadius.circular(11)),
                                      child: Center(child: Text(project.name.substring(0, math.min(project.name.length, 1)), style: const TextStyle(color: Color(0xFF0a0f1a), fontWeight: FontWeight.bold, fontSize: 18))),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFFf1f5f9))),
                                          const SizedBox(height: 3),
                                          Row(children: [const Icon(Icons.location_on, size: 12, color: Color(0xFF64748b)), const SizedBox(width: 3), Expanded(child: Text(project.location.isEmpty ? '未填写地点' : project.location, style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 12), overflow: TextOverflow.ellipsis))]),
                                          const SizedBox(height: 2),
                                          Row(children: [
                                            const Icon(Icons.business, size: 12, color: Color(0xFF64748b)),
                                            const SizedBox(width: 3),
                                            Expanded(child: Text(project.company.isEmpty ? '未填写单位' : project.company, style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 12), overflow: TextOverflow.ellipsis)),
                                            const SizedBox(width: 8),
                                            const Icon(Icons.person, size: 12, color: Color(0xFF64748b)),
                                            const SizedBox(width: 3),
                                            Flexible(child: Text(project.manager.isEmpty ? '未填写' : project.manager, style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 12), overflow: TextOverflow.ellipsis)),
                                          ]),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(builder: (_) => ChatScreen(project: project)),
                                        ).then((_) => _refreshUnread());
                                      },
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(7),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF111827),
                                              borderRadius: BorderRadius.circular(9),
                                              border: Border.all(color: const Color(0xFF00d4ff).withOpacity(0.4)),
                                            ),
                                            child: const Icon(Icons.chat_bubble_outline, size: 16, color: Color(0xFF00d4ff)),
                                          ),
                                          if ((_unread[project.id] ?? 0) > 0)
                                            Positioned(
                                              right: 0, top: 0,
                                              child: Container(
                                                padding: const EdgeInsets.all(3),
                                                decoration: const BoxDecoration(color: Color(0xFFef4444), shape: BoxShape.circle),
                                                constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                                                child: Text(
                                                  '${_unread[project.id]}',
                                                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: projects.length,
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF00d4ff), size: 18),
                  SizedBox(width: 12),
                  Text('创建项目功能请在管理后台使用', style: TextStyle(color: Color(0xFF00d4ff), fontSize: 15)),
                ],
              ),
              backgroundColor: const Color(0xFF1a2332),
              behavior: SnackBarBehavior.floating,
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFF00d4ff), width: 1.5),
              ),
              margin: const EdgeInsets.all(16),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('新建项目'),
      ),
    );
  }
}
