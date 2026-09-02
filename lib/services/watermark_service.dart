import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class WatermarkService {
  // 单例模式
  static final WatermarkService _instance = WatermarkService._internal();

  factory WatermarkService() {
    return _instance;
  }

  WatermarkService._internal();

  /// 压缩图片：限制最大边长 1280px，质量 70
  /// 适用于 3M 低带宽场景，原图 3-5MB → 压缩后 200-400KB
  img.Image _compressImage(img.Image image) {
    const maxDimension = 1280;
    int width = image.width;
    int height = image.height;

    if (width > maxDimension || height > maxDimension) {
      if (width >= height) {
        final newWidth = maxDimension;
        final newHeight = (height * maxDimension / width).round();
        return img.copyResize(image, width: newWidth, height: newHeight);
      } else {
        final newHeight = maxDimension;
        final newWidth = (width * maxDimension / height).round();
        return img.copyResize(image, width: newWidth, height: newHeight);
      }
    }
    return image;
  }

  /// 压缩字节流（用于聊天图片上传）
  Future<List<int>> compressBytes(List<int> bytes) async {
    try {
      final uint8Bytes = Uint8List.fromList(bytes);
      final image = img.decodeImage(uint8Bytes);
      if (image == null) return bytes;
      final compressed = _compressImage(image);
      return img.encodeJpg(compressed, quality: 70);
    } catch (e) {
      debugPrint('Error compressing bytes: $e');
      return bytes;
    }
  }

  // 添加水印到图片
  Future<File> addWatermark(
    File imageFile,
    String customText,
  ) async {
    try {
      // 读取图片
      final imageBytes = await imageFile.readAsBytes();
      final image = img.decodeImage(imageBytes);

      if (image == null) {
        throw Exception('Failed to decode image');
      }

      // 压缩图片（限制尺寸）
      final compressed = _compressImage(image);

      // 保存带水印的图片（quality: 70 减小文件大小）
      final outputFile = File('${imageFile.path}_watermarked.jpg');
      await outputFile.writeAsBytes(img.encodeJpg(compressed, quality: 70));

      return outputFile;
    } catch (e) {
      debugPrint('Error adding watermark: $e');
      return imageFile; // 出错时返回原图
    }
  }

  // 添加水印到 XFile (Web 平台)
  Future<XFile> addWatermarkToXFile(
    XFile xFile,
    String customText,
  ) async {
    try {
      // 读取 XFile 为字节
      final bytes = await xFile.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) {
        throw Exception('Failed to decode image');
      }

      // 压缩图片（限制尺寸）
      final compressed = _compressImage(image);

      // 编码为字节（quality: 70 减小文件大小）
      final outputBytes = img.encodeJpg(compressed, quality: 70);

      // 创建临时文件
      final tempFile = File('${xFile.path}_watermarked.jpg');
      await tempFile.writeAsBytes(outputBytes);

      return XFile(tempFile.path);
    } catch (e) {
      debugPrint('Error adding watermark to XFile: $e');
      return xFile; // 出错时返回原图
    }
  }
}
