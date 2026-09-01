import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:construction_app/models/project.dart';
import 'package:construction_app/models/construction_log.dart';
import 'package:construction_app/services/api_service.dart';
import 'package:construction_app/services/watermark_service.dart';
import 'package:construction_app/widgets/photo_picker_widget.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

class LogFormScreen extends StatefulWidget {
  final Project project;
  const LogFormScreen({super.key, required this.project});
  @override
  State<LogFormScreen> createState() => _LogFormScreenState();
}

class _LogFormScreenState extends State<LogFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _dateController = TextEditingController();
  final _temperatureController = TextEditingController();
  final _windForceController = TextEditingController();
  final _windDirectionController = TextEditingController();
  final _constructionPartController = TextEditingController();
  final _constructionContentController = TextEditingController();
  final _progressController = TextEditingController();
  final _constructionRecordController = TextEditingController();
  final _technicalSafetyRecordController = TextEditingController();
  final _materialRecordController = TextEditingController();
  final _projectManagerController = TextEditingController();
  final _recorderController = TextEditingController();
  final _watermarkTextController = TextEditingController();

  String _weather = '晴';
  final List<String> _weatherOptions = ['晴', '多云', '阴', '小雨', '中雨', '大雨', '雪', '雷阵雨', '雾'];

  List<dynamic> _sitePhotos = [];
  List<dynamic> _certificatePhotos = [];
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _dateController.text = _formatDate(DateTime.now());
    _watermarkTextController.text = widget.project.name;
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: Color(0xFF00d4ff))),
          child: child!,
        );
      },
    );
    if (picked != null) {
      _dateController.text = _formatDate(picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final watermarkedPhotos = await _addWatermarksToPhotos(_sitePhotos);
      final watermarkedCertificates = await _addWatermarksToPhotos(_certificatePhotos);
      final log = ConstructionLog(
        projectId: widget.project.id,
        date: DateTime.parse(_dateController.text),
        weather: _weather,
        temperature: _temperatureController.text,
        windForce: _windForceController.text,
        windDirection: _windDirectionController.text,
        constructionPart: _constructionPartController.text,
        constructionContent: _constructionContentController.text,
        progress: _progressController.text,
        constructionRecord: _constructionRecordController.text,
        technicalSafetyRecord: _technicalSafetyRecordController.text,
        materialRecord: _materialRecordController.text,
        projectManager: _projectManagerController.text,
        recorder: _recorderController.text,
      );
      await ApiService().createLog(log, watermarkedPhotos, watermarkedCertificates);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('日志提交成功'),
            ],
          ),
          backgroundColor: const Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('提交失败：$e')),
            ],
          ),
          backgroundColor: const Color(0xFFE53935),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  Future<List<dynamic>> _addWatermarksToPhotos(List<dynamic> photos) async {
    final watermarkedPhotos = <dynamic>[];
    final watermarkService = WatermarkService();
    for (var photo in photos) {
      if (kIsWeb) {
        final xFile = photo as XFile;
        watermarkedPhotos.add(await watermarkService.addWatermarkToXFile(xFile, _watermarkTextController.text));
      } else {
        final file = photo as File;
        watermarkedPhotos.add(await watermarkService.addWatermark(file, _watermarkTextController.text));
      }
    }
    return watermarkedPhotos;
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
            backgroundColor: const Color(0xFF1a2332),
            leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
            flexibleSpace: FlexibleSpaceBar(
              title: const Text('录入施工日志', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFFf1f5f9))),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0a0f1a), Color(0xFF1a2332)],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -30,
                      top: -30,
                      child: Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0x1000d4ff)),
                      ),
                    ),
                    Positioned(
                      left: -20,
                      bottom: -20,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0x2000d4ff)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check),
                tooltip: '提交',
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(Icons.calendar_month, '日期与天气', const Color(0xFF00d4ff)),
                    const SizedBox(height: 12),
                    _buildCard([
                      Row(children: [
                        Expanded(child: _buildFormField('日期', Icons.calendar_today, _dateController, readOnly: true, onTap: _selectDate, validator: (v) => v!.isEmpty ? '请选择日期' : null)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildDropdownField('天气', Icons.cloud, _weather, _weatherOptions, (v) => setState(() => _weather = v!))),
                      ]),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(child: _buildFormField('气温', Icons.thermostat, _temperatureController, hintText: '例如：35°C')),
                        const SizedBox(width: 12),
                        Expanded(child: _buildFormField('风力', Icons.air, _windForceController, hintText: '例如：3级')),
                      ]),
                      const SizedBox(height: 16),
                      _buildFormField('风向', Icons.north_east, _windDirectionController, hintText: '例如：东风'),
                    ]),
                    const SizedBox(height: 24),
                    _buildSectionHeader(Icons.engineering, '工程信息', const Color(0xFFFF9800)),
                    const SizedBox(height: 12),
                    _buildCard([
                      _buildFormField('当日工程施工部位', Icons.location_on, _constructionPartController, hintText: '例如：主体结构'),
                      const SizedBox(height: 16),
                      _buildFormField('当日工程施工内容', Icons.build, _constructionContentController, maxLines: 2, hintText: '详细描述施工内容'),
                      const SizedBox(height: 16),
                      _buildFormField('当日工程形象进度', Icons.timeline, _progressController, hintText: '例如：完成70%'),
                    ]),
                    const SizedBox(height: 24),
                    _buildSectionHeader(Icons.description, '施工情况记录', const Color(0xFF4CAF50)),
                    const SizedBox(height: 12),
                    _buildCard([_buildFormField('施工情况记录', Icons.note_add, _constructionRecordController, maxLines: 4, hintText: '部位项目、机械作业、班组工作、施工存在问题等', validator: (v) => v!.isEmpty ? '请填写施工情况记录' : null)]),
                    const SizedBox(height: 24),
                    _buildSectionHeader(Icons.security, '技术质量安全记录', const Color(0xFFE91E63)),
                    const SizedBox(height: 12),
                    _buildCard([_buildFormField('技术质量安全工作记录', Icons.verified_user, _technicalSafetyRecordController, maxLines: 4, hintText: '技术质量安全活动、技术质量安全问题、检查评定验收等')]),
                    const SizedBox(height: 24),
                    _buildSectionHeader(Icons.inventory_2, '材料进场记录', const Color(0xFF9C27B0)),
                    const SizedBox(height: 12),
                    _buildCard([_buildFormField('今日材料、构配件进场、检(试)验情况记录', Icons.local_shipping, _materialRecordController, maxLines: 3, hintText: '详细记录材料进场情况')]),
                    const SizedBox(height: 24),
                    _buildSectionHeader(Icons.people, '负责人信息', const Color(0xFF00BCD4)),
                    const SizedBox(height: 12),
                    _buildCard([
                      Row(children: [
                        Expanded(child: _buildFormField('工程负责人', Icons.person, _projectManagerController, validator: (v) => v!.isEmpty ? '请填写工程负责人' : null)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildFormField('记录人', Icons.person_outline, _recorderController, validator: (v) => v!.isEmpty ? '请填写记录人' : null)),
                      ]),
                    ]),
                    const SizedBox(height: 24),
                    _buildSectionHeader(Icons.water_drop, '水印设置', const Color(0xFF00BCD4)),
                    const SizedBox(height: 12),
                    _buildCard([_buildFormField('自定义水印文本', Icons.text_fields, _watermarkTextController, hintText: '例如：XX项目')]),
                    const SizedBox(height: 24),
                    _buildSectionHeader(Icons.photo_library, '现场照片', const Color(0xFFFF5722)),
                    const SizedBox(height: 12),
                    _buildCard([PhotoPickerWidget(photos: _sitePhotos, onPhotosChanged: (photos) => setState(() => _sitePhotos = photos), label: '添加现场照片')]),
                    const SizedBox(height: 24),
                    _buildSectionHeader(Icons.assignment, '合格证照片', const Color(0xFF795548)),
                    const SizedBox(height: 12),
                    _buildCard([PhotoPickerWidget(photos: _certificatePhotos, onPhotosChanged: (photos) => setState(() => _certificatePhotos = photos), label: '添加合格证照片')]),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00d4ff),
                          foregroundColor: const Color(0xFF0a0f1a),
                          elevation: 4,
                          shadowColor: const Color(0xFF00d4ff).withOpacity(0.4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _isSubmitting ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0a0f1a))) : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.send, size: 20), SizedBox(width: 8), Text('提交日志', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))]),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title, Color color) {
    return Row(children: [
      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: color, size: 22)),
      const SizedBox(width: 12),
      Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
    ]);
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a2332),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2d3a4f)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: Container(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children))),
    );
  }

  Widget _buildFormField(String label, IconData icon, TextEditingController controller, {int maxLines = 1, String? hintText, bool readOnly = false, VoidCallback? onTap, String? Function(String?)? validator}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, size: 16, color: const Color(0xFF64748b)), const SizedBox(width: 6), Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF94a3b8)))]),
      const SizedBox(height: 8),
      TextFormField(
        controller: controller,
        style: const TextStyle(color: Color(0xFFf1f5f9)),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: Color(0xFF64748b), fontSize: 14),
          filled: true,
          fillColor: const Color(0xFF111827),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2d3a4f))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2d3a4f))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF00d4ff), width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFef4444), width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        maxLines: maxLines,
        readOnly: readOnly,
        onTap: onTap,
        validator: validator,
      ),
    ]);
  }

  Widget _buildDropdownField(String label, IconData icon, String value, List<String> items, ValueChanged<String?> onChanged) {
    List<DropdownMenuItem<String>> dropdownItems = items.map((item) {
      return DropdownMenuItem<String>(
        value: item,
        child: Text(item, style: const TextStyle(fontSize: 14, color: Color(0xFFf1f5f9))),
      );
    }).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, size: 16, color: const Color(0xFF64748b)), const SizedBox(width: 6), Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF94a3b8)))]),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF2d3a4f))),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF00d4ff)),
            dropdownColor: const Color(0xFF1a2332),
            items: dropdownItems,
            onChanged: onChanged,
          ),
        ),
      ),
    ]);
  }

  @override
  void dispose() {
    _dateController.dispose();
    _temperatureController.dispose();
    _windForceController.dispose();
    _windDirectionController.dispose();
    _constructionPartController.dispose();
    _constructionContentController.dispose();
    _progressController.dispose();
    _constructionRecordController.dispose();
    _technicalSafetyRecordController.dispose();
    _materialRecordController.dispose();
    _projectManagerController.dispose();
    _recorderController.dispose();
    _watermarkTextController.dispose();
    super.dispose();
  }
}
