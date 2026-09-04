import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:construction_app/models/project.dart';
import 'package:construction_app/services/api_service.dart';
import 'package:construction_app/services/auth_service.dart';
import 'package:construction_app/services/chat_service.dart';
import 'package:construction_app/screens/chat_screen.dart';

class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key});

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  late Future<List<Project>> _projectsFuture;
  Map<int, int> _unread = {};
  bool _showChatEntry = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _refreshProjects();
    _refreshUnread();
  }

  void _refreshProjects() {
    _projectsFuture = ApiService().getProjects();
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
                return const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
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
