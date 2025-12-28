import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/leaf_analysis_service.dart';

class LeafAnalysisScreen extends StatefulWidget {
  const LeafAnalysisScreen({super.key});

  @override
  State<LeafAnalysisScreen> createState() => _LeafAnalysisScreenState();
}

class _LeafAnalysisScreenState extends State<LeafAnalysisScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isProcessing = false;
  LeafAnalysisResult? _analysisResult;
  final LeafAnalysisService _analysisService = LeafAnalysisService();
  
  // Zoom and Focus
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _baseZoom = 1.0;
  Offset? _focusPoint;
  bool _showFocusIndicator = false;
  
  // Show result screen
  bool _showResult = false;
  File? _capturedImage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
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

  Future<void> _takePictureAndAnalyze() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final XFile photo = await _controller!.takePicture();
      final File imageFile = File(photo.path);

      final result = await _analysisService.analyzeLeafColor(imageFile);

      setState(() {
        _analysisResult = result;
        _capturedImage = imageFile;
        _isProcessing = false;
        _showResult = true;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
        );
      }
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
              ? Colors.teal
              : isAvailable 
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.05),
          shape: BoxShape.circle,
          border: Border.all(
            color: isActive 
                ? Colors.teal 
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

  String _getNitrogenLevel() {
    if (_analysisResult == null) return 'ไม่ทราบ';
    final green = _analysisResult!.averageGreen;
    if (green < 100) return 'ต่ำ';
    if (green > 180) return 'สูงเกินไป';
    return 'พอเหมาะ';
  }

  Color _getNitrogenColor() {
    final level = _getNitrogenLevel();
    switch (level) {
      case 'Low':
        return Colors.orange;
      case 'Too High':
        return Colors.red;
      default:
        return Colors.green;
    }
  }

  double _getNitrogenPosition() {
    if (_analysisResult == null) return 0.5;
    final green = _analysisResult!.averageGreen;
    // Map 0-255 to 0-1
    return (green / 255).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showResult && _analysisResult != null) {
      return _buildResultScreen();
    }
    return _buildCameraScreen();
  }

  Widget _buildCameraScreen() {
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
                  color: const Color(0x30A5D6A7), // Light green tint
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'วิเคราะห์สีใบข้าว',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), // Placeholder for symmetry
                ],
              ),
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
              bottom: 180,
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
                  GestureDetector(
                    onTap: _isProcessing ? null : _takePictureAndAnalyze,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
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
                          : const Icon(
                              Icons.eco,
                              color: Colors.green,
                              size: 36,
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'เล็งกล้องไปที่ใบข้าว',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Loading overlay
          if (_isProcessing)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.5),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'กำลังวิเคราะห์สีใบข้าว...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
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

  Widget _buildResultScreen() {
    final nitrogenLevel = _getNitrogenLevel();
    final nitrogenColor = _getNitrogenColor();
    final nitrogenPosition = _getNitrogenPosition();
    
    return Scaffold(
      backgroundColor: const Color(0xFFE8F5E9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF2E7D32)),
          onPressed: () {
            setState(() {
              _showResult = false;
              _analysisResult = null;
            });
          },
        ),
        title: const Text(
          'ผลวิเคราะห์สีใบข้าว',
          style: TextStyle(
            color: Color(0xFF2E7D32),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Leaf Color Scale
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'สเกลสีใบข้าว',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Color scale bar
                  Container(
                    height: 12,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFFFF9C4), // Light yellow
                          Color(0xFFAED581), // Light green
                          Color(0xFF2E7D32), // Dark green
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Indicator
                  Stack(
                    children: [
                      const SizedBox(height: 30, width: double.infinity),
                      Positioned(
                        left: (MediaQuery.of(context).size.width - 80) * nitrogenPosition,
                        child: Column(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: nitrogenColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Labels
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'ไนโตรเจนต่ำ',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        'พอเหมาะ',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        'ไนโตรเจนสูง',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Nitrogen Level Result
            Center(
              child: Text(
                'ระดับไนโตรเจน: $nitrogenLevel',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2E7D32),
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Warning/Info Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: nitrogenColor.withValues(alpha: 0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        nitrogenLevel == 'Optimal' 
                            ? Icons.check_circle_outline 
                            : Icons.warning_amber_rounded,
                        color: nitrogenColor,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _getWarningTitle(nitrogenLevel),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: nitrogenColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _getWarningMessage(nitrogenLevel),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // RGB Values Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'การวิเคราะห์สี',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildColorValue('R', _analysisResult!.averageR, Colors.red),
                      _buildColorValue('G', _analysisResult!.averageG, Colors.green),
                      _buildColorValue('B', _analysisResult!.averageB, Colors.blue),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Average color display
                  Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: Color.fromRGBO(
                        _analysisResult!.averageR,
                        _analysisResult!.averageG,
                        _analysisResult!.averageB,
                        1.0,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Center(
                      child: Text(
                        'สีใบข้าวที่ตรวจพบ',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              blurRadius: 4.0,
                              color: Colors.black26,
                              offset: Offset(1.0, 1.0),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Scan Again Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _showResult = false;
                    _analysisResult = null;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'สแกนใบอื่น',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorValue(String label, int value, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  String _getWarningTitle(String level) {
    switch (level) {
      case 'ต่ำ':
        return 'คำเตือน: ไนโตรเจนต่ำ';
      case 'สูงเกินไป':
        return 'คำเตือน: ไนโตรเจนสูงเกินไป';
      default:
        return 'ระดับไนโตรเจนพอเหมาะ';
    }
  }

  String _getWarningMessage(String level) {
    switch (level) {
      case 'ต่ำ':
        return 'แนะนำให้เติมปุ๋ยไนโตรเจน (เช่น ยูเรีย) เพื่อช่วยการเจริญเติบโตและสีใบ';
      case 'สูงเกินไป':
        return 'หยุดใส่ปุ๋ยยูเรียทันทีเพื่อป้องกันการระบาดของเพลี้ยและรักษาสุขภาพต้นข้าว';
      default:
        return 'ต้นข้าวของคุณมีไนโตรเจนในระดับเหมาะสม ให้ดูแลตามปกติต่อไป';
    }
  }
}

class LeafAnalysisResult {
  final int averageR;
  final int averageG;
  final int averageB;
  final double averageGreen;
  final double greenStandard;
  final bool isHealthy;

  LeafAnalysisResult({
    required this.averageR,
    required this.averageG,
    required this.averageB,
    required this.averageGreen,
    required this.greenStandard,
    required this.isHealthy,
  });
}
