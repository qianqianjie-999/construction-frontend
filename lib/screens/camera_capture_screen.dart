import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// 自定义相机页：支持广角/超广角焦段切换。
/// 拍照成功后 pop 返回 XFile；取消返回 null。
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _backCameras = [];
  int _cameraIndex = 0;
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
      _initController(_backCameras[_cameraIndex]);
    }
  }

  Future<void> _setupCameras() async {
    try {
      final cams = await availableCameras();
      _backCameras =
          cams.where((c) => c.lensDirection == CameraLensDirection.back).toList();
      if (_backCameras.isEmpty) {
        setState(() {
          _error = '未检测到后置摄像头';
          _initializing = false;
        });
        return;
      }
      // 优先选主摄（通常是列表第一个后置）
      await _initController(_backCameras.first);
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

  /// 切换到下一个后置摄像头（主摄/超广角/长焦，取决于设备暴露的镜头）
  Future<void> _switchCamera() async {
    if (_backCameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _backCameras.length;
    await _initController(_backCameras[_cameraIndex]);
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
    try {
      final XFile file = await c.takePicture();
      if (mounted) Navigator.pop(context, file);
    } catch (e) {
      if (mounted) {
        setState(() => _taking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拍照失败：$e')),
        );
      }
    }
  }

  /// 焦段按钮：广角(≤0.7x) / 1x / 2x(若支持)
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

  bool _isZoomActive(double target) =>
      (_currentZoom - target).abs() < 0.06;

  @override
  Widget build(BuildContext context) {
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
                _backCameras.length > 1
                    ? '镜头 ${_cameraIndex + 1}/${_backCameras.length}'
                    : '',
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
                  // 焦段切换
                  if (_controller != null && _zoomOptions.length > 1)
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
                                  color: active
                                      ? Colors.black
                                      : Colors.white,
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
                        // 多镜头切换按钮
                        SizedBox(
                          width: 64,
                          child: _backCameras.length > 1
                              ? IconButton(
                                  onPressed: _initializing ? null : _switchCamera,
                                  icon: const Icon(Icons.cameraswitch,
                                      color: Colors.white, size: 30),
                                )
                              : const SizedBox.shrink(),
                        ),
                        const SizedBox(width: 24),
                        // 快门
                        GestureDetector(
                          onTap: _initializing || _taking ? null : _takePicture,
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
                        const SizedBox(width: 24),
                        // 占位保持快门居中
                        const SizedBox(width: 64),
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
