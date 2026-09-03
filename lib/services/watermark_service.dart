import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class WatermarkService {
  static final WatermarkService _instance = WatermarkService._internal();
  factory WatermarkService() => _instance;
  WatermarkService._internal();

  /// 压缩图片：限制最大边长 1280px
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

  /// 格式化经纬度
  String _formatGps(double? lat, double? lng) {
    if (lat == null || lng == null) return '';
    String latDir = lat >= 0 ? 'N' : 'S';
    String lngDir = lng >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(6)}°$latDir ${lng.abs().toStringAsFixed(6)}°$lngDir';
  }

  /// 在图片上画水印（项目名 + 日期时间 + 经纬度）
  img.Image _drawWatermark(img.Image image, String text, {double? latitude, double? longitude}) {
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final w = image.width;
    final h = image.height;

    final padding = (w * 0.015).round().clamp(8, 20);
    final gpsStr = _formatGps(latitude, longitude);
    // 项目名 + 日期 + GPS（有就显示）
    final lineCount = gpsStr.isEmpty ? 2 : 3;
    final lineH = 18;
    final barHeight = lineH * lineCount + padding * 2;

    // 画半透明黑色背景条
    for (var y = h - barHeight - padding; y < h - padding; y++) {
      for (var x = padding; x < w - padding; x++) {
        if (x >= 0 && x < w && y >= 0 && y < h) {
          final pixel = image.getPixel(x, y);
          image.setPixel(x, y, img.ColorRgba8(
            (pixel.r * 0.45).round(),
            (pixel.g * 0.45).round(),
            (pixel.b * 0.45).round(),
            255,
          ));
        }
      }
    }

    // 画文字
    final font = img.arial14;
    final textX = padding + 6;
    var textY = h - barHeight - padding + padding ~/ 2;

    // 第一行：项目名（白色）
    img.drawString(image, text, font: font, x: textX, y: textY, color: img.ColorRgba8(255, 255, 255, 255));
    textY += lineH;

    // 第二行：日期时间（白色）
    img.drawString(image, dateStr, font: font, x: textX, y: textY, color: img.ColorRgba8(255, 255, 255, 255));
    textY += lineH;

    // 第三行：经纬度（蓝色，有就显示）
    if (gpsStr.isNotEmpty) {
      img.drawString(image, gpsStr, font: font, x: textX, y: textY, color: img.ColorRgba8(0, 220, 255, 255));
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

  /// 添加水印到图片（压缩 + 画水印文字 + 经纬度）
  Future<File> addWatermark(File imageFile, String customText, {double? latitude, double? longitude}) async {
    try {
      final imageBytes = await imageFile.readAsBytes();
      final image = img.decodeImage(imageBytes);
      if (image == null) throw Exception('Failed to decode image');

      final compressed = _compressImage(image);
      final watermarked = _drawWatermark(compressed, customText, latitude: latitude, longitude: longitude);

      final outputFile = File('${imageFile.path}_watermarked.jpg');
      await outputFile.writeAsBytes(img.encodeJpg(watermarked, quality: 70));
      return outputFile;
    } catch (e) {
      debugPrint('Error adding watermark: $e');
      return imageFile;
    }
  }

  /// 添加水印到 XFile（压缩 + 画水印文字 + 经纬度）
  Future<XFile> addWatermarkToXFile(XFile xFile, String customText, {double? latitude, double? longitude}) async {
    try {
      final bytes = await xFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) throw Exception('Failed to decode image');

      final compressed = _compressImage(image);
      final watermarked = _drawWatermark(compressed, customText, latitude: latitude, longitude: longitude);

      final outputBytes = img.encodeJpg(watermarked, quality: 70);
      final tempFile = File('${xFile.path}_watermarked.jpg');
      await tempFile.writeAsBytes(outputBytes);
      return XFile(tempFile.path);
    } catch (e) {
      debugPrint('Error adding watermark to XFile: $e');
      return xFile;
    }
  }
}
