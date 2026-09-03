import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';

/// 图片保存到相册服务
class ImageSaveService {
  static final ImageSaveService _instance = ImageSaveService._internal();
  factory ImageSaveService() => _instance;
  ImageSaveService._internal();

  /// 从 URL 下载图片并保存到相册
  /// 返回 (成功, 消息)
  Future<(bool, String)> saveFromUrl(String url) async {
    try {
      // 1. 请求权限
      final status = await _requestPermission();
      if (!status) {
        return (false, '没有存储权限，请在设置中开启');
      }

      // 2. 下载图片
      final dio = Dio();
      final response = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.data == null || response.data!.isEmpty) {
        return (false, '下载失败：图片为空');
      }

      // 3. 保存到相册
      final result = await ImageGallerySaver.saveImage(
        Uint8List.fromList(response.data!),
        quality: 100,
        name: 'construction_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (result['isSuccess'] == true) {
        return (true, '已保存到相册');
      } else {
        return (false, '保存失败');
      }
    } catch (e) {
      return (false, '保存失败：$e');
    }
  }

  /// 请求存储权限
  Future<bool> _requestPermission() async {
    // Android 13+ 使用 READ_MEDIA_IMAGES
    // 低版本使用 WRITE_EXTERNAL_STORAGE
    final statuses = await [
      Permission.storage,
      Permission.photos,
    ].request();

    // 只要有一个授权通过即可
    return statuses.values.any((s) => s.isGranted || s.isLimited);
  }
}
