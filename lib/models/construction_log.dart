import '../services/api_service.dart';

class ConstructionLog {
  final int? id; // 上传后由服务器分配
  final int projectId;
  final DateTime date;
  final String weather;
  final String temperature; // 气温
  final String windForce; // 风力
  final String windDirection; // 风向
  final String constructionPart; // 当日工程施工部位
  final String constructionContent; // 当日工程施工内容
  final String progress; // 当日工程形象进度
  final String constructionRecord; // 施工情况记录
  final String technicalSafetyRecord; // 技术质量安全工作记录
  final String materialRecord; // 今日材料、构配件进场、检(试)验情况记录
  final String projectManager; // 工程负责人
  final String recorder; // 记录人
  final List<LogPhoto> photos; // 现场照片

  ConstructionLog({
    this.id,
    required this.projectId,
    required this.date,
    required this.weather,
    required this.temperature,
    required this.windForce,
    required this.windDirection,
    required this.constructionPart,
    required this.constructionContent,
    required this.progress,
    required this.constructionRecord,
    required this.technicalSafetyRecord,
    required this.materialRecord,
    required this.projectManager,
    required this.recorder,
    this.photos = const [],
  });

  factory ConstructionLog.fromJson(Map<String, dynamic> json) {
    final photosJson = json['photos'] as List? ?? [];
    return ConstructionLog(
      id: json['id'],
      projectId: json['project_id'],
      date: DateTime.parse(json['date']),
      weather: json['weather'] ?? '',
      temperature: json['temperature'] ?? '',
      windForce: json['wind_force'] ?? '',
      windDirection: json['wind_direction'] ?? '',
      constructionPart: json['construction_part'] ?? '',
      constructionContent: json['construction_content'] ?? '',
      progress: json['progress'] ?? '',
      constructionRecord: json['construction_record'] ?? '',
      technicalSafetyRecord: json['technical_safety_record'] ?? '',
      materialRecord: json['material_record'] ?? '',
      projectManager: json['project_manager'] ?? '',
      recorder: json['recorder'] ?? '',
      photos: photosJson.map((e) => LogPhoto.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'project_id': projectId,
      'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'weather': weather,
      'temperature': temperature,
      'wind_force': windForce,
      'wind_direction': windDirection,
      'construction_part': constructionPart,
      'construction_content': constructionContent,
      'progress': progress,
      'construction_record': constructionRecord,
      'technical_safety_record': technicalSafetyRecord,
      'material_record': materialRecord,
      'project_manager': projectManager,
      'recorder': recorder,
    };
  }

  String get dateStr => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  String get weekdayStr => ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][date.weekday % 7];
}

/// 日志照片
class LogPhoto {
  final int? id;
  final String filename;
  final String? originalFilename;
  final String photoType;  // 'site' 现场照片, 'certificate' 合格证
  final String url;        // 相对路径 /api/photos/xxx

  LogPhoto({
    this.id,
    required this.filename,
    this.originalFilename,
    required this.photoType,
    required this.url,
  });

  factory LogPhoto.fromJson(Map<String, dynamic> json) {
    return LogPhoto(
      id: json['id'] as int?,
      filename: json['filename'] as String? ?? '',
      originalFilename: json['original_filename'] as String?,
      photoType: json['photo_type'] as String? ?? 'site',
      url: json['url'] as String? ?? '',
    );
  }

  /// 拼接完整图片 URL
  String get fullUrl {
    if (url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    return '${ApiService.instance.baseUrl}$url';
  }
}
