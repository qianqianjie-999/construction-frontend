import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// 自定义相机页：支持广角/超广角（后置多镜头切换 + 变焦焦段）、前后摄像头自拍。
/// 拍照成功后 pop 返回 XFile（像素已按方向转正）；取消返回 null。
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  final List<CameraDescription> _backCameras = [];
  CameraDescription? _frontCamera;
  int _backIndex = 0;
  bool _isFront = false;
  bool _initializing = true;
  bool _taking = false;
  String? _error;

  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupCameras();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initController(_currentCamera);
    }
  }

  CameraDescription get _currentCamera =>
      _isFront ? _frontCamera! : _backCameras[_backIndex];

  Future<void> _setupCameras() async {
    try {
      final cams = await availableCameras();
      for (final c in cams) {
        if (c.lensDirection == CameraLensDirection.back) {
          _backCameras.add(c);
        } else if (c.lensDirection == CameraLensDirection.front &&
            _frontCamera == null) {
          _frontCamera = c;
        }
      }
      if (_backCameras.isEmpty && _frontCamera == null) {
        setState(() {
          _error = '未检测到摄像头';
          _initializing = false;
        });
        return;
      }
      // 默认后置主摄；无后置才用前置
      _isFront = _backCameras.isEmpty;
      await _initController(_currentCamera);
    } catch (e) {
      setState(() {
        _error = '无法启动相机：$e';
        _initializing = false;
      });
    }
  }

  Future<void> _initController(CameraDescription cam) async {
    final old = _controller;
    _controller = null;
    if (old != null) {
      await old.dispose();
    }
    setState(() => _initializing = true);

    final c = CameraController(cam, ResolutionPreset.high, enableAudio: false);
    try {
      await c.initialize();
      _minZoom = await c.getMinZoomLevel();
      _maxZoom = await c.getMaxZoomLevel();
      _currentZoom = 1.0;
      if (mounted) {
        setState(() {
          _controller = c;
          _initializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '相机初始化失败：$e';
          _initializing = false;
        });
      }
    }
  }

  /// 前置/后置翻转（自拍）
  Future<void> _flipCamera() async {
    if (_initializing) return;
    if (_isFront) {
      if (_backCameras.isEmpty) return;
      _isFront = false;
    } else {
      if (_frontCamera == null) return;
      _isFront = true;
    }
    await _initController(_currentCamera);
  }

  /// 后置多镜头循环：主摄 → 广角/超广角 → 长焦（设备暴露几个就循环几个）
  Future<void> _cycleBackLens() async {
    if (_initializing || _backCameras.length < 2 || _isFront) return;
    _backIndex = (_backIndex + 1) % _backCameras.length;
    await _initController(_currentCamera);
  }

  Future<void> _setZoom(double z) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final clamped = z.clamp(_minZoom, _maxZoom);
    await c.setZoomLevel(clamped);
    setState(() => _currentZoom = clamped);
  }

  Future<void> _takePicture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _taking) return;
    setState(() => _taking = true);
    XFile? raw;
    try {
      // 关键修复：插件 takePicture 默认不更新采集旋转（相机开屏时的方向），
      // 竖屏进相机 → 横屏拍照会得到"竖图横内容"，水印随之错位。
      // 拍摄前显式锁定为当前手机方向，插件按传感器方向正确旋转。
      await c.lockCaptureOrientation(c.value.deviceOrientation);
      raw = await c.takePicture();
    } catch (e) {
      if (mounted) {
        setState(() => _taking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拍照失败：$e')),
        );
      }
      return;
    } finally {
      try {
        await c.unlockCaptureOrientation();
      } catch (_) {}
    }
    XFile result = raw;
    // 像素处理：EXIF 方向转正（保证横拍出横图、水印方向正确）+ 前置镜像
    try {
      final src = img.decodeImage(await raw.readAsBytes());
      if (src != null) {
        var oriented = img.bakeOrientation(src);
        if (_isFront) {
          oriented = img.flipHorizontal(oriented);
        }
        final outPath =
            '${Directory.systemTemp.path}/cam_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(outPath).writeAsBytes(img.encodeJpg(oriented, quality: 92));
        result = XFile(outPath);
      }
    } catch (e) {
      debugPrint('照片方向处理失败，使用原图: $e');
    }
    if (mounted) Navigator.pop(context, result);
  }

  /// 变焦焦段按钮：广角(≤0.7x) / 1x / 2x(若支持)。仅后置显示
  List<({String label, double zoom})> get _zoomOptions {
    final opts = <({String label, double zoom})>[];
    if (_minZoom < 0.9) {
      opts.add((label: '广角${_minZoom.toStringAsFixed(1)}x', zoom: _minZoom));
    }
    opts.add((label: '1x', zoom: 1.0));
    if (_maxZoom >= 1.9) {
      opts.add((label: '2x', zoom: 2.0.clamp(_minZoom, _maxZoom)));
    }
    return opts;
  }

  bool _isZoomActive(double target) => (_currentZoom - target).abs() < 0.06;

  /// 后置镜头名（多镜头时提示）
  String get _lensLabel {
    if (_isFront) return '自拍模式';
    if (_backCameras.length < 2) return '';
    const names = ['主摄', '广角', '长焦'];
    final n = _backIndex < names.length ? names[_backIndex] : '镜头${_backIndex + 1}';
    return '$n ${_backIndex + 1}/${_backCameras.length}';
  }

  @override
  Widget build(BuildContext context) {
    final showZoom =
        !_isFront && _controller != null && _zoomOptions.length > 1;
    final canFlip = _frontCamera != null && _backCameras.isNotEmpty;
    final canCycleLens = !_isFront && _backCameras.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // 相机预览
            Positioned.fill(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(_error!,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 15),
                            textAlign: TextAlign.center),
                      ),
                    )
                  : _initializing || _controller == null
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFF00d4ff)))
                      : Center(
                          child: AspectRatio(
                            aspectRatio: 1 / _controller!.value.aspectRatio,
                            child: CameraPreview(_controller!),
                          ),
                        ),
            ),

            // 顶部栏：关闭
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Positioned(
              top: 14,
              right: 16,
              child: Text(
                _lensLabel,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),

            // 底部控制区
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                children: [
                  // 变焦焦段切换（仅后置）
                  if (showZoom)
                    Container(
                      margin: const EdgeInsets.only(bottom: 18),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: _zoomOptions.map((o) {
                          final active = _isZoomActive(o.zoom);
                          return GestureDetector(
                            onTap: () => _setZoom(o.zoom),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: active
                                    ? const Color(0xFF00d4ff)
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                o.label,
                                style: TextStyle(
                                  color:
                                      active ? Colors.black : Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  // 快门行
                  Padding(
                    padding: const EdgeInsets.only(bottom: 28),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 左：前后翻转（自拍）
                        SizedBox(
                          width: 64,
                          child: canFlip
                              ? IconButton(
                                  onPressed:
                                      _initializing ? null : _flipCamera,
                                  icon: const Icon(Icons.flip_camera_ios,
                                      color: Colors.white, size: 30),
                                )
                              : const SizedBox.shrink(),
                        ),
                        const SizedBox(width: 20),
                        // 快门
                        GestureDetector(
                          onTap:
                              _initializing || _taking ? null : _takePicture,
                          child: Container(
                            width: 74,
                            height: 74,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(5),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _taking
                                      ? Colors.white54
                                      : const Color(0xFF00d4ff),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        // 右：后置多镜头循环（主摄/广角/长焦）
                        SizedBox(
                          width: 64,
                          child: canCycleLens
                              ? IconButton(
                                  onPressed:
                                      _initializing ? null : _cycleBackLens,
                                  icon: const Icon(Icons.cameraswitch,
                                      color: Color(0xFF00d4ff), size: 30),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
