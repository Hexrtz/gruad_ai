import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import '../services/pest_analysis_service.dart';
import '../models/pest_result.dart';
import 'analysis_summary_screen.dart';

class PestCameraScreen extends StatefulWidget {
  final int targetPhotoCount;
  final int areaSize;

  const PestCameraScreen({
    super.key,
    this.targetPhotoCount = 5,
    this.areaSize = 4,
  });

  @override
  State<PestCameraScreen> createState() => _PestCameraScreenState();
}

class _PestCameraScreenState extends State<PestCameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isAnalyzing = false;
  final List<File> _capturedImages = [];
  final Map<File, PestResult> _imageResults = {};
  Interpreter? _interpreter;
  PestAnalysisService? _analysisService;
  
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
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      
      _minZoom = await _controller!.getMinZoomLevel();
      _maxZoom = await _controller!.getMaxZoomLevel();
      _currentZoom = _minZoom;
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
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
      debugPrint('Model loaded successfully');
    } catch (e) {
      debugPrint('Failed to load model: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถโหลด AI model: $e')),
        );
      }
    }
  }

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

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final XFile photo = await _controller!.takePicture();
      final File imageFile = File(photo.path);
      
      setState(() {
        _capturedImages.add(imageFile);
        _isProcessing = false;
      });

      // ถ้าถ่ายครบตามจำนวนแล้ว ให้วิเคราะห์ทั้งหมด
      if (_capturedImages.length >= widget.targetPhotoCount) {
        _analyzeAllImages();
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการถ่ายรูป: $e')),
        );
      }
    }
  }

  Future<void> _analyzeAllImages() async {
    if (_capturedImages.isEmpty || _analysisService == null) {
      return;
    }

    setState(() {
      _isAnalyzing = true;
    });

    try {
      int totalPests = 0;
      List<PestDetection> allDetections = [];

      for (var imageFile in _capturedImages) {
        final result = await _analysisService!.analyzeImage(imageFile);
        _imageResults[imageFile] = result;
        totalPests += result.totalPests;
        allDetections.addAll(result.detections);
      }

      // คำนวณความหนาแน่นต่อพื้นที่
      // 1 ตารางวา = 4 ตารางเมตร
      final areaInSquareMeters = widget.areaSize * 4.0;
      final density = totalPests / areaInSquareMeters;

      setState(() {
        _isAnalyzing = false;
      });

      // ไปหน้าสรุปผล
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => AnalysisSummaryScreen(
              capturedImages: _capturedImages,
              imageResults: _imageResults,
              totalPests: totalPests,
              areaSize: widget.areaSize,
              density: density,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการวิเคราะห์: $e')),
        );
      }
    }
  }

  void _removeLastImage() {
    if (_capturedImages.isNotEmpty) {
      setState(() {
        final lastImage = _capturedImages.removeLast();
        _imageResults.remove(lastImage);
      });
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
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isActive
              ? Colors.orange
              : isAvailable 
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.05),
          shape: BoxShape.circle,
          border: Border.all(
            color: isActive 
                ? Colors.orange 
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
              fontSize: 10,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _interpreter?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remainingPhotos = widget.targetPhotoCount - _capturedImages.length;
    final progress = _capturedImages.length / widget.targetPhotoCount;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full screen camera
          _isInitialized && _controller != null
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      onScaleStart: _handleScaleStart,
                      onScaleUpdate: _handleScaleUpdate,
                      onTapDown: (details) => _handleTapToFocus(details, constraints),
                      child: SizedBox.expand(
                        child: CameraPreview(_controller!),
                      ),
                    );
                  },
                )
              : Container(
                  color: Colors.black,
                  child: const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),

          // Semi-transparent overlay
          if (_isInitialized && _controller != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: const Color(0x40D7CCC8),
                ),
              ),
            ),

          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Close button
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
                  // Progress indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '${_capturedImages.length}/${widget.targetPhotoCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Area info
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${widget.areaSize} ตร.ว.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Progress bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: 20,
            right: 20,
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  remainingPhotos > 0 
                      ? 'เหลืออีก $remainingPhotos รูป'
                      : 'ครบแล้ว! กำลังวิเคราะห์...',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Center guide frame
          if (_isInitialized && _controller != null)
            Center(
              child: Container(
                width: 240,
                height: 180,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.8),
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
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
                    ),
                  );
                },
              ),
            ),

          // Zoom controls
          if (_isInitialized && _controller != null)
            Positioned(
              left: 16,
              bottom: 220,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_currentZoom.toStringAsFixed(1)}x',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildZoomChip(1.0, '1x'),
                    const SizedBox(height: 4),
                    _buildZoomChip(2.0, '2x'),
                    const SizedBox(height: 4),
                    _buildZoomChip(3.0, '3x'),
                  ],
                ),
              ),
            ),

          // Captured images thumbnails
          if (_capturedImages.isNotEmpty)
            Positioned(
              left: 16,
              bottom: 130,
              child: SizedBox(
                height: 60,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  shrinkWrap: true,
                  itemCount: _capturedImages.length,
                  itemBuilder: (context, index) {
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white, width: 2),
                        image: DecorationImage(
                          image: FileImage(_capturedImages[index]),
                          fit: BoxFit.cover,
                        ),
                      ),
                      child: index == _capturedImages.length - 1
                          ? GestureDetector(
                              onTap: _removeLastImage,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            )
                          : null,
                    );
                  },
                ),
              ),
            ),

          // Bottom section
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 30, 20, 50),
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
                  // Capture button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Undo button
                      if (_capturedImages.isNotEmpty)
                        GestureDetector(
                          onTap: _removeLastImage,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.undo,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      const SizedBox(width: 24),
                      // Main capture button
                      GestureDetector(
                        onTap: (_isProcessing || _capturedImages.length >= widget.targetPhotoCount)
                            ? null
                            : _takePicture,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _capturedImages.length >= widget.targetPhotoCount
                                ? Colors.green
                                : Colors.white,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.5),
                              width: 4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: _isProcessing
                              ? const Center(
                                  child: SizedBox(
                                    width: 30,
                                    height: 30,
                                    child: CircularProgressIndicator(strokeWidth: 3),
                                  ),
                                )
                              : Icon(
                                  _capturedImages.length >= widget.targetPhotoCount
                                      ? Icons.check
                                      : Icons.camera_alt,
                                  color: _capturedImages.length >= widget.targetPhotoCount
                                      ? Colors.white
                                      : Colors.grey.shade700,
                                  size: 32,
                                ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      // Analyze button (visible when photos are complete)
                      if (_capturedImages.length >= widget.targetPhotoCount)
                        GestureDetector(
                          onTap: _isAnalyzing ? null : _analyzeAllImages,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.analytics,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 48),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Instruction text
                  Text(
                    _capturedImages.length >= widget.targetPhotoCount
                        ? 'ถ่ายครบแล้ว! กดปุ่มวิเคราะห์'
                        : 'เล็งกล้องไปที่โคนกอข้าว แล้วถ่ายรูป',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Analyzing overlay
          if (_isAnalyzing)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.7),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'กำลังวิเคราะห์รูปภาพ...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_capturedImages.length} รูป',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
