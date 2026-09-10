import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class WatermarkService {
  static final WatermarkService _instance = WatermarkService._internal();
  factory WatermarkService() => _instance;
  WatermarkService._internal();

  /// 品牌 logo（assets 中缓存，只加载一次）
  ui.Image? _logoCache;
  Future<ui.Image?> _loadLogo() async {
    if (_logoCache != null) return _logoCache;
    try {
      final data = await rootBundle.load('assets/images/watermark_logo.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      _logoCache = (await codec.getNextFrame()).image;
      return _logoCache;
    } catch (e) {
      debugPrint('logo 加载失败: $e');
      return null;
    }
  }

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
  ///   左下角多行信息（经度/纬度/地址/时间/项目/备注，均可开关），
  ///   白色字 + 阴影，无背景框；右下角应用角标。
  /// 同时限制最长边 1280px 并输出 JPEG。
  Future<Uint8List> _makeWatermarkedBytes(
    Uint8List bytes,
    String text, {
    double? latitude,
    double? longitude,
    String? address,
    String? note,
    bool showLongitude = true,
    bool showLatitude = true,
    bool showAddress = true,
    bool showTime = true,
    bool showProject = true,
    bool showNote = true,
    bool showLogo = true,
  }) async {
    const maxDim = 1280;

    // 先按 EXIF 方向把像素转正（Flutter 画布不识别 EXIF orientation，
    // 否则横拍照片水印会画错边）；已转正的图直接用原字节，避免二次压缩
    var decodedBytes = bytes;
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded != null && (decoded.exif.imageIfd.orientation ?? 1) > 1) {
        decodedBytes =
            img.encodeJpg(img.bakeOrientation(decoded), quality: 95);
      }
    } catch (e) {
      debugPrint('EXIF 方向处理失败: $e');
    }

    final codec = await ui.instantiateImageCodec(decodedBytes);
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

    // ---- 左下角水印区（从下往上：备注黄条 / 信息块 / 品牌logo） ----
    // 横拍（长边为水平）时按短边（高）缩放字号，水印块更紧凑，始终贴着底部长边
    final isLandscape = w > h;
    final shortSide = math.min(w, h);
    final infoFontSize =
        (shortSide * (isLandscape ? 0.052 : 0.042)).clamp(15.0, 27.0);
    final lineHeight = isLandscape ? 1.38 : 1.55;
    final pad = shortSide * 0.035;
    const textShadow = [
      Shadow(color: Color(0xFF000000), blurRadius: 4, offset: Offset(1.0, 1.0)),
      Shadow(color: Color(0xFF000000), blurRadius: 4, offset: Offset(-1.0, 1.0)),
      Shadow(color: Color(0xFF000000), blurRadius: 2, offset: Offset(0, 0)),
    ];

    final lines = <InlineSpan>[];
    void addLine(String label, String value) {
      lines.add(TextSpan(children: [
        TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.w700)),
        TextSpan(text: value),
      ]));
    }

    if (showLongitude && longitude != null) {
      addLine('经度: ', longitude.toStringAsFixed(6));
    }
    if (showLatitude && latitude != null) {
      addLine('纬度: ', latitude.toStringAsFixed(6));
    }
    final addr = address?.trim() ?? '';
    if (showAddress && addr.isNotEmpty) {
      addLine('地址: ', addr);
    }
    if (showTime) {
      addLine('时间: ', timeStr);
    }
    if (showProject && text.trim().isNotEmpty) {
      addLine('项目: ', text.trim());
    }
    final noteStr = note?.trim() ?? '';
    final hasNote = showNote && noteStr.isNotEmpty;

    // 从底部往上排
    double cursorY = h - pad;

    // ① 备注黄底高亮条（仿今日水印相机）
    if (hasNote) {
      final noteTp = TextPainter(
        text: TextSpan(
          text: '备注: $noteStr',
          style: TextStyle(
            color: const Color(0xFFFFFFFF),
            fontSize: infoFontSize * 0.92,
            fontWeight: FontWeight.w700,
            height: 1.4,
            shadows: textShadow,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 3,
        ellipsis: '…',
      )..layout(maxWidth: w - pad * 2 - infoFontSize);
      final barPadY = infoFontSize * 0.32;
      final barPadX = infoFontSize * 0.55;
      final barH = noteTp.height + barPadY * 2;
      final barW = noteTp.width + barPadX * 2;
      final barTop = cursorY - barH;
      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(pad * 0.5, barTop, barW, barH),
        Radius.circular(infoFontSize * 0.3),
      );
      canvas.drawRRect(
          barRect, Paint()..color = const Color(0xE6FFC400));
      noteTp.paint(canvas, Offset(pad * 0.5 + barPadX, barTop + barPadY));
      cursorY = barTop - infoFontSize * 0.45;
    }

    // ② 信息块（经纬度/地址/时间/项目）
    if (lines.isNotEmpty) {
      final infoTp = TextPainter(
        text: TextSpan(
          style: TextStyle(
            color: const Color(0xFFFFFFFF),
            fontSize: infoFontSize,
            height: lineHeight,
            fontWeight: FontWeight.w500,
            shadows: textShadow,
          ),
          children: [
            for (var i = 0; i < lines.length; i++)
              TextSpan(
                  children: [
                    lines[i],
                    if (i < lines.length - 1) const TextSpan(text: '\n'),
                  ]),
          ],
        ),
        textDirection: TextDirection.ltr,
        maxLines: 7,
        ellipsis: '…',
      )..layout(maxWidth: w - pad * 2);
      final infoTop = cursorY - infoTp.height;
      infoTp.paint(canvas, Offset(pad, infoTop));
      cursorY = infoTop - infoFontSize * 0.55;
    }

    // ③ 品牌 logo（科威达真实 logo，白色圆角衬底保证任何背景清晰）
    if (showLogo) {
      final logo = await _loadLogo();
      if (logo != null) {
        final logoH = infoFontSize * (isLandscape ? 2.4 : 2.6);
        final logoW = logoH * logo.width / logo.height;
        final logoPad = infoFontSize * 0.35;
        final blockW = logoW + logoPad * 2;
        final blockH = logoH + logoPad * 2;
        final blockLeft = pad * 0.5;
        final blockTop = cursorY - blockH;
        // 白色圆角衬底
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(blockLeft, blockTop, blockW, blockH),
            Radius.circular(infoFontSize * 0.4),
          ),
          Paint()..color = const Color(0xF2FFFFFF),
        );
        // logo 图
        canvas.drawImageRect(
          logo,
          Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
          Rect.fromLTWH(blockLeft + logoPad, blockTop + logoPad, logoW, logoH),
          Paint()..filterQuality = FilterQuality.high,
        );
      }
    }

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
      {double? latitude,
      double? longitude,
      String? address,
      String? note,
      bool showLongitude = true,
      bool showLatitude = true,
      bool showAddress = true,
      bool showTime = true,
      bool showProject = true,
      bool showNote = true,
      bool showLogo = true}) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final out = await _makeWatermarkedBytes(
        Uint8List.fromList(bytes),
        customText,
        latitude: latitude,
        longitude: longitude,
        address: address,
        note: note,
        showLongitude: showLongitude,
        showLatitude: showLatitude,
        showAddress: showAddress,
        showTime: showTime,
        showProject: showProject,
        showNote: showNote,
        showLogo: showLogo,
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
      {double? latitude,
      double? longitude,
      String? address,
      String? note,
      bool showLongitude = true,
      bool showLatitude = true,
      bool showAddress = true,
      bool showTime = true,
      bool showProject = true,
      bool showNote = true,
      bool showLogo = true}) async {
    try {
      final bytes = await xFile.readAsBytes();
      final out = await _makeWatermarkedBytes(
        Uint8List.fromList(bytes),
        customText,
        latitude: latitude,
        longitude: longitude,
        address: address,
        note: note,
        showLongitude: showLongitude,
        showLatitude: showLatitude,
        showAddress: showAddress,
        showTime: showTime,
        showProject: showProject,
        showNote: showNote,
        showLogo: showLogo,
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
