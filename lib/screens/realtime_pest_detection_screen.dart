import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import '../services/pest_analysis_service.dart';
import '../models/pest_result.dart';

class RealtimePestDetectionScreen extends StatefulWidget {
  const RealtimePestDetectionScreen({super.key});

  @override
  State<RealtimePestDetectionScreen> createState() =>
      _RealtimePestDetectionScreenState();
}

class _RealtimePestDetectionScreenState
    extends State<RealtimePestDetectionScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isDetecting = false;
  Interpreter? _interpreter;
  PestAnalysisService? _analysisService;
  PestResult? _currentResult;
  int _totalPestsDetected = 0;
  
  // Zoom and Focus
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _baseZoom = 1.0;
  Offset? _focusPoint;
  bool _showFocusIndicator = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadModel();
      _initializeCamera();
    });
  }

  Future<void> _initializeCamera() async {
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ต้องการสิทธิ์ในการใช้กล้อง')),
          );
        }
        return;
      }

      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ไม่พบกล้อง')),
          );
        }
        return;
      }

      _controller = CameraController(
        _cameras![0],
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
      
      // Initialize zoom levels
      _minZoom = await _controller!.getMinZoomLevel();
      _maxZoom = await _controller!.getMaxZoomLevel();
      _currentZoom = _minZoom;
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        // เริ่ม real-time detection
        _startRealtimeDetection();
      }
    } catch (e, stackTrace) {
      debugPrint('Camera initialization error: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _isInitialized = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการเปิดกล้อง: $e')),
        );
      }
    }
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/yolov8n.tflite');
      _analysisService = PestAnalysisService(_interpreter!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ โมเดลพร้อมใช้งาน')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ โหลดโมเดลไม่สำเร็จ: $e')),
        );
      }
    }
  }

  // Zoom functions
  Future<void> _setZoomLevel(double zoom) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    
    final newZoom = zoom.clamp(_minZoom, _maxZoom);
    await _controller!.setZoomLevel(newZoom);
    setState(() {
      _currentZoom = newZoom;
    });
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseZoom = _currentZoom;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final newZoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
    _setZoomLevel(newZoom);
  }

  // Focus functions
  Future<void> _handleTapToFocus(TapDownDetails details, BoxConstraints constraints) async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    final x = details.localPosition.dx / constraints.maxWidth;
    final y = details.localPosition.dy / constraints.maxHeight;

    try {
      await _controller!.setFocusPoint(Offset(x, y));
      await _controller!.setExposurePoint(Offset(x, y));
      
      setState(() {
        _focusPoint = details.localPosition;
        _showFocusIndicator = true;
      });

      // Hide focus indicator after 1.5 seconds
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() {
            _showFocusIndicator = false;
          });
        }
      });
    } catch (e) {
      debugPrint('Focus error: $e');
    }
  }

  Widget _buildZoomChip(double zoom, String label) {
    final isActive = (_currentZoom - zoom).abs() < 0.1;
    final targetZoom = zoom.clamp(_minZoom, _maxZoom);
    final isAvailable = zoom >= _minZoom && zoom <= _maxZoom;
    
    return GestureDetector(
      onTap: isAvailable ? () => _setZoomLevel(targetZoom) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isActive
              ? Colors.purple
              : isAvailable 
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.05),
          shape: BoxShape.circle,
          border: Border.all(
            color: isActive 
                ? Colors.purple 
                : isAvailable
                    ? Colors.white.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.1),
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isAvailable ? Colors.white : Colors.white.withValues(alpha: 0.3),
              fontSize: 11,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  void _startRealtimeDetection() {
    if (_controller == null || !_controller!.value.isInitialized) {
      debugPrint('❌ Camera not initialized');
      return;
    }

    if (_analysisService == null) {
      debugPrint('❌ Analysis service not ready');
      return;
    }

    debugPrint('✅ Starting real-time detection...');
    
    DateTime? lastProcessTime;
    const minInterval = Duration(milliseconds: 500); // วิเคราะห์ทุก 0.5 วินาที

    _controller!.startImageStream((CameraImage image) async {
      final now = DateTime.now();
      
      // ตรวจสอบว่าเวลาผ่านไปเพียงพอแล้วหรือยัง
      if (lastProcessTime != null && 
          now.difference(lastProcessTime!) < minInterval) {
        return; // ข้าม frame นี้
      }

      if (!_isDetecting && _analysisService != null) {
        _isDetecting = true;
        lastProcessTime = now;
        
        try {
          debugPrint('🔄 Processing frame...');
          final result = await _processCameraImage(image);
          
          if (mounted && result != null) {
            debugPrint('✅ Detected ${result.totalPests} pests');
            setState(() {
              _currentResult = result;
              _totalPestsDetected = result.totalPests;
            });
          } else {
            debugPrint('⚠️ No result or result is null');
          }
        } catch (e, stackTrace) {
          debugPrint('❌ Detection error: $e');
          debugPrint('Stack trace: $stackTrace');
        } finally {
          _isDetecting = false;
        }
      }
    });
  }

  Future<PestResult?> _processCameraImage(CameraImage image) async {
    if (_analysisService == null) {
      debugPrint('❌ Analysis service is null');
      return null;
    }

    try {
      // แปลง CameraImage เป็น img.Image
      final img.Image? convertedImage = _convertCameraImageToImage(image);
      if (convertedImage == null) {
        debugPrint('❌ Failed to convert camera image');
        return null;
      }

      debugPrint('✅ Image converted: ${convertedImage.width}x${convertedImage.height}');

      // บันทึกเป็นไฟล์ชั่วคราว
      final tempFile = await _saveImageToTempFile(convertedImage);
      if (tempFile == null) {
        debugPrint('❌ Failed to save temp file');
        return null;
      }

      debugPrint('✅ Temp file saved: ${tempFile.path}');

      // วิเคราะห์
      final result = await _analysisService!.analyzeImage(tempFile);
      
      // ลบไฟล์ชั่วคราว
      try {
        await tempFile.delete();
      } catch (_) {}

      return result;
    } catch (e, stackTrace) {
      debugPrint('❌ Process camera image error: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  img.Image? _convertCameraImageToImage(CameraImage cameraImage) {
    try {
      debugPrint('📸 Converting image: format=${cameraImage.format.group}, size=${cameraImage.width}x${cameraImage.height}');
      
      if (cameraImage.format.group == ImageFormatGroup.yuv420) {
        return _convertYUV420ToImage(cameraImage);
      } else if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
        return _convertBGRA8888ToImage(cameraImage);
      } else {
        debugPrint('⚠️ Unsupported image format: ${cameraImage.format.group}');
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Convert camera image error: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  img.Image _convertYUV420ToImage(CameraImage cameraImage) {
    final width = cameraImage.width;
    final height = cameraImage.height;
    final planes = cameraImage.planes;
    
    debugPrint('📊 YUV420 planes count: ${planes.length}');
    
    final yBuffer = planes[0].bytes;
    final yRowStride = planes[0].bytesPerRow;
    final yPixelStride = planes[0].bytesPerPixel ?? 1;

    final image = img.Image(width: width, height: height);

    // ตรวจสอบว่าเป็น YUV420 แบบ 2 planes (interleaved UV) หรือ 3 planes (แยก U, V)
    if (planes.length == 2) {
      // YUV420 แบบ 2 planes: plane[0] = Y, plane[1] = interleaved UV
      final uvBuffer = planes[1].bytes;
      final uvRowStride = planes[1].bytesPerRow;
      final uvPixelStride = planes[1].bytesPerPixel ?? 2; // UV interleaved = 2 bytes per pixel

      for (int y = 0; y < height; y++) {
        final yIndex = y * yRowStride;
        final uvIndex = (y ~/ 2) * uvRowStride;

        for (int x = 0; x < width; x++) {
          final yPixel = yBuffer[yIndex + (x * yPixelStride)];
          final uvOffset = (x ~/ 2) * uvPixelStride;
          
          // UV interleaved: U, V, U, V, ...
          final uPixel = uvBuffer[uvIndex + uvOffset];
          final vPixel = uvBuffer[uvIndex + uvOffset + 1];

          // แปลง YUV เป็น RGB
          final r = _yuvToR(yPixel, uPixel, vPixel);
          final g = _yuvToG(yPixel, uPixel, vPixel);
          final b = _yuvToB(yPixel, uPixel, vPixel);

          image.setPixel(x, y, img.ColorRgb8(r, g, b));
        }
      }
    } else if (planes.length >= 3) {
      // YUV420 แบบ 3 planes: plane[0] = Y, plane[1] = U, plane[2] = V
      final uBuffer = planes[1].bytes;
      final vBuffer = planes[2].bytes;
      final uvRowStride = planes[1].bytesPerRow;
      final uvPixelStride = planes[1].bytesPerPixel ?? 1;

      for (int y = 0; y < height; y++) {
        final yIndex = y * yRowStride;
        final uvIndex = (y ~/ 2) * uvRowStride;

        for (int x = 0; x < width; x++) {
          final yPixel = yBuffer[yIndex + (x * yPixelStride)];
          final uvOffset = (x ~/ 2) * uvPixelStride;
          final uPixel = uBuffer[uvIndex + uvOffset];
          final vPixel = vBuffer[uvIndex + uvOffset];

          // แปลง YUV เป็น RGB
          final r = _yuvToR(yPixel, uPixel, vPixel);
          final g = _yuvToG(yPixel, uPixel, vPixel);
          final b = _yuvToB(yPixel, uPixel, vPixel);

          image.setPixel(x, y, img.ColorRgb8(r, g, b));
        }
      }
    } else {
      throw Exception('Unsupported YUV420 format: expected 2 or 3 planes, got ${planes.length}');
    }

    return image;
  }

  int _yuvToR(int y, int u, int v) {
    final r = (y + (1.402 * (v - 128))).round().clamp(0, 255);
    return r;
  }

  int _yuvToG(int y, int u, int v) {
    final g = (y - (0.344 * (u - 128)) - (0.714 * (v - 128))).round().clamp(0, 255);
    return g;
  }

  int _yuvToB(int y, int u, int v) {
    final b = (y + (1.772 * (u - 128))).round().clamp(0, 255);
    return b;
  }

  img.Image _convertBGRA8888ToImage(CameraImage cameraImage) {
    final width = cameraImage.width;
    final height = cameraImage.height;
    final bgraBytes = cameraImage.planes[0].bytes;

    final image = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final index = (y * width + x) * 4;
        final b = bgraBytes[index];
        final g = bgraBytes[index + 1];
        final r = bgraBytes[index + 2];
        // final a = bgraBytes[index + 3]; // Alpha channel

        image.setPixel(x, y, img.ColorRgb8(r, g, b));
      }
    }

    return image;
  }

  Future<File?> _saveImageToTempFile(img.Image image) async {
    try {
      final bytes = img.encodeJpg(image);
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/temp_camera_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(bytes);
      return tempFile;
    } catch (e) {
      debugPrint('Save temp file error: $e');
      return null;
    }
  }

  void _stopDetection() {
    _controller?.stopImageStream();
    setState(() {
      _isDetecting = false;
      _currentResult = null;
    });
  }

  @override
  void dispose() {
    _stopDetection();
    _controller?.dispose();
    _interpreter?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // กล้อง
          if (_isInitialized && _controller != null)
            SizedBox.expand(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      GestureDetector(
                        onScaleStart: _handleScaleStart,
                        onScaleUpdate: _handleScaleUpdate,
                        onTapDown: (details) => _handleTapToFocus(details, constraints),
                        child: CameraPreview(_controller!),
                      ),
                      // วาด bounding boxes แบบ real-time
                      if (_currentResult != null && _currentResult!.detections.isNotEmpty)
                        CustomPaint(
                          painter: RealtimeBoundingBoxPainter(
                            detections: _currentResult!.detections,
                            previewWidth: _controller!.value.previewSize?.height ?? 1,
                            previewHeight: _controller!.value.previewSize?.width ?? 1,
                            displayWidth: constraints.maxWidth,
                            displayHeight: constraints.maxHeight,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      // Focus indicator
                      if (_showFocusIndicator && _focusPoint != null)
                        Positioned(
                          left: _focusPoint!.dx - 30,
                          top: _focusPoint!.dy - 30,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 1.2, end: 1.0),
                            duration: const Duration(milliseconds: 200),
                            builder: (context, scale, child) {
                              return Transform.scale(
                                scale: scale,
                                child: Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.yellow,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.center_focus_strong,
                                    color: Colors.yellow,
                                    size: 24,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      // Zoom controls - compact left side
                      Positioned(
                        left: 12,
                        bottom: 120,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Zoom level
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.purple,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_currentZoom.toStringAsFixed(1)}x',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Zoom buttons
                              _buildZoomChip(1.0, '1x'),
                              const SizedBox(height: 4),
                              _buildZoomChip(2.0, '2x'),
                              const SizedBox(height: 4),
                              _buildZoomChip(3.0, '3x'),
                            ],
                          ),
                        ),
                      ),
                      // Tap to focus hint
                      if (!_showFocusIndicator)
                        Positioned(
                          top: 200,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.touch_app, color: Colors.white.withValues(alpha: 0.8), size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    'แตะเพื่อโฟกัส',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.8),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            )
          else
            Container(
              color: Colors.black,
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
          
          // Top bar with close button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  // Stats pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bug_report, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'รวม: $_totalPestsDetected',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          width: 1,
                          height: 16,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        const Icon(Icons.visibility, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'ตรวจพบ: ${_currentResult?.detections.length ?? 0}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),
          
          // Bottom section with gradient and control button
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 50),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
              ),
              child: Column(
                children: [
                  // Start/Stop button
                  GestureDetector(
                    onTap: () {
                      if (_isDetecting) {
                        _stopDetection();
                      } else {
                        _startRealtimeDetection();
                      }
                      setState(() {});
                    },
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isDetecting ? Colors.red : Colors.green,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.5),
                          width: 4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_isDetecting ? Colors.red : Colors.green)
                                .withValues(alpha: 0.4),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Icon(
                        _isDetecting ? Icons.stop : Icons.play_arrow,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isDetecting ? 'แตะเพื่อหยุดตรวจจับ' : 'แตะเพื่อเริ่มตรวจจับแบบเรียลไทม์',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RealtimeBoundingBoxPainter extends CustomPainter {
  final List<PestDetection> detections;
  final double previewWidth;
  final double previewHeight;
  final double displayWidth;
  final double displayHeight;

  RealtimeBoundingBoxPainter({
    required this.detections,
    required this.previewWidth,
    required this.previewHeight,
    required this.displayWidth,
    required this.displayHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // คำนวณ scale factor ระหว่าง preview และ display
    // Camera preview อาจมี aspect ratio ต่างจากหน้าจอ
    final previewAspect = previewWidth / previewHeight;
    final displayAspect = displayWidth / displayHeight;
    
    double scaleX, scaleY, offsetX, offsetY;
    
    if (displayAspect > previewAspect) {
      // Display กว้างกว่า preview (letterbox)
      scaleY = displayHeight / previewHeight;
      scaleX = scaleY;
      offsetX = (displayWidth - previewWidth * scaleX) / 2;
      offsetY = 0;
    } else {
      // Display สูงกว่า preview (pillarbox)
      scaleX = displayWidth / previewWidth;
      scaleY = scaleX;
      offsetX = 0;
      offsetY = (displayHeight - previewHeight * scaleY) / 2;
    }
    
    // Paint สำหรับ bounding box
    final boxPaint = Paint()
      ..color = Colors.red.shade600
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    // Paint สำหรับ label background
    final labelBgPaint = Paint()
      ..color = Colors.red.shade600
      ..style = PaintingStyle.fill;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (final detection in detections) {
      // Scale และ offset bounding box
      final x = detection.x * scaleX + offsetX;
      final y = detection.y * scaleY + offsetY;
      final w = detection.width * scaleX;
      final h = detection.height * scaleY;
      
      // วาดสี่เหลี่ยม
      final rect = Rect.fromLTWH(x, y, w, h);
      canvas.drawRect(rect, boxPaint);

      // วาดข้อความ confidence
      final confidenceText = '${(detection.confidence * 100).toStringAsFixed(0)}%';
      textPainter.text = TextSpan(
        text: confidenceText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      
      // วาด background สำหรับข้อความ (rounded rectangle)
      final textRect = Rect.fromLTWH(
        x,
        y - 26,
        textPainter.width + 12,
        textPainter.height + 8,
      );
      
      // วาด rounded rectangle
      final rrect = RRect.fromRectAndRadius(textRect, const Radius.circular(6));
      canvas.drawRRect(rrect, labelBgPaint);
      
      textPainter.paint(
        canvas,
        Offset(x + 6, y - 24),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

