import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class WatermarkService {
  static final WatermarkService _instance = WatermarkService._internal();
  factory WatermarkService() => _instance;
  WatermarkService._internal();

  /// 压缩图片：限制最大边长 1280px（相册图上传用，不加水印）
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

  /// 压缩字节流（用于聊天相册图片上传，不加水印）
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

  /// 仿"元道经纬相机"水印：
  ///   左下角多行信息（经度/纬度/地址/时间/项目），白色字 + 黑色描边，无背景框
  ///   画面中央半透明"现场拍照"大字
  ///   右下角倾斜"工程现场管理"角标
  /// 同时限制最长边 1280px 并输出 JPEG。
  Future<Uint8List> _makeWatermarkedBytes(
    Uint8List bytes,
    String text, {
    double? latitude,
    double? longitude,
    String? address,
  }) async {
    const maxDim = 1280;

    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final src = frame.image;
    final sw = src.width;
    final sh = src.height;

    final scale = math.min(1.0, maxDim / math.max(sw, sh));
    final w = (sw * scale).round();
    final h = (sh * scale).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawImageRect(
      src,
      Rect.fromLTWH(0, 0, sw.toDouble(), sh.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    src.dispose();

    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final timeStr =
        '${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}:${two(now.second)}';

    // ---- 左下角信息块（白字 + 阴影，亮背景也清晰） ----
    final infoFontSize = (w * 0.033).clamp(13.0, 21.0);
    final lines = <InlineSpan>[];
    void addLine(String label, String value, {Color? valueColor}) {
      lines.add(TextSpan(children: [
        TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.w600)),
        TextSpan(text: value, style: TextStyle(color: valueColor)),
      ]));
    }

    if (latitude != null && longitude != null) {
      addLine('经度: ', longitude.toStringAsFixed(6));
      addLine('纬度: ', latitude.toStringAsFixed(6));
    }
    final addr = address?.trim() ?? '';
    if (addr.isNotEmpty) {
      addLine('地址: ', addr);
    }
    addLine('时间: ', timeStr);
    if (text.trim().isNotEmpty) {
      addLine('项目: ', text.trim());
    }

    final infoStyle = TextStyle(
      color: const Color(0xFFFFFFFF),
      fontSize: infoFontSize,
      height: 1.5,
      shadows: const [
        Shadow(color: Color(0xFF000000), blurRadius: 3, offset: Offset(0.8, 0.8)),
        Shadow(color: Color(0xFF000000), blurRadius: 3, offset: Offset(-0.8, 0.8)),
      ],
    );

    final infoTp = TextPainter(
      text: TextSpan(style: infoStyle, children: [
        for (var i = 0; i < lines.length; i++)
          TextSpan(children: [lines[i], if (i < lines.length - 1) const TextSpan(text: '\n')]),
      ]),
      textDirection: TextDirection.ltr,
      maxLines: 6,
      ellipsis: '…',
    );
    final pad = w * 0.035;
    infoTp.layout(maxWidth: w - pad * 2);
    infoTp.paint(canvas, Offset(pad, h - infoTp.height - pad * 0.9));

    // ---- 右下角倾斜角标 ----
    final brandTp = TextPainter(
      text: TextSpan(
        text: '工程现场管理',
        style: TextStyle(
          color: const Color(0xFFFFFFFF).withOpacity(0.75),
          fontSize: infoFontSize * 0.72,
          fontWeight: FontWeight.w500,
          shadows: const [
            Shadow(color: Color(0xCC000000), blurRadius: 2, offset: Offset(1, 1)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    brandTp.layout();
    canvas.save();
    canvas.translate(w - pad * 0.5, h - pad * 0.35);
    canvas.rotate(-0.22);
    brandTp.paint(canvas, Offset(-brandTp.width, -brandTp.height));
    canvas.restore();

    final picture = recorder.endRecording();
    final outImg = await picture.toImage(w, h);
    // ui.toByteData 不支持 JPEG，先出 PNG 再用 image 包转 JPEG（控制体积）
    final pngData =
        await outImg.toByteData(format: ui.ImageByteFormat.png);
    outImg.dispose();
    if (pngData == null) throw Exception('水印图编码失败');
    final composed = img.decodeImage(pngData.buffer.asUint8List());
    if (composed == null) throw Exception('水印图解码失败');
    return Uint8List.fromList(img.encodeJpg(composed, quality: 75));
  }

  /// 添加水印到图片文件，失败时返回原图
  Future<File> addWatermark(File imageFile, String customText,
      {double? latitude, double? longitude, String? address}) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final out = await _makeWatermarkedBytes(
        Uint8List.fromList(bytes),
        customText,
        latitude: latitude,
        longitude: longitude,
        address: address,
      );
      final outputFile = File('${imageFile.path}_watermarked.jpg');
      await outputFile.writeAsBytes(out);
      return outputFile;
    } catch (e) {
      debugPrint('Error adding watermark: $e');
      return imageFile;
    }
  }

  /// 添加水印到 XFile（聊天/日志拍照用），失败时返回原 XFile
  Future<XFile> addWatermarkToXFile(XFile xFile, String customText,
      {double? latitude, double? longitude, String? address}) async {
    try {
      final bytes = await xFile.readAsBytes();
      final out = await _makeWatermarkedBytes(
        Uint8List.fromList(bytes),
        customText,
        latitude: latitude,
        longitude: longitude,
        address: address,
      );
      final tempFile = File('${xFile.path}_watermarked.jpg');
      await tempFile.writeAsBytes(out);
      return XFile(tempFile.path);
    } catch (e) {
      debugPrint('Error adding watermark to XFile: $e');
      return xFile;
    }
  }
}
