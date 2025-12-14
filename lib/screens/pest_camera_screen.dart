import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import '../services/pest_analysis_service.dart';
import '../models/pest_result.dart';
import '../widgets/image_with_boxes.dart';

class PestCameraScreen extends StatefulWidget {
  const PestCameraScreen({super.key});

  @override
  State<PestCameraScreen> createState() => _PestCameraScreenState();
}

class _PestCameraScreenState extends State<PestCameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isProcessing = false;
  final List<File> _capturedImages = [];
  final Map<File, PestResult> _imageResults = {}; // เก็บผลการวิเคราะห์ของแต่ละรูป
  Interpreter? _interpreter;
  PestAnalysisService? _analysisService;
  PestResult? _lastResult;

  @override
  void initState() {
    super.initState();
    // เรียก async functions โดยไม่ block UI
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadModel();
      _initializeCamera();
    });
  }

  Future<void> _initializeCamera() async {
    try {
      // ขออนุญาตใช้กล้อง
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
        ResolutionPreset.medium, // เปลี่ยนจาก high เป็น medium เพื่อลด memory
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
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

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    try {
      final XFile photo = await _controller!.takePicture();
      final File imageFile = File(photo.path);
      
      setState(() {
        _capturedImages.add(imageFile);
      });

      // วิเคราะห์ภาพทันที
      if (_analysisService != null) {
        await _analyzeImage(imageFile);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการถ่ายรูป: $e')),
        );
      }
    }
  }

  Future<void> _analyzeImage(File imageFile) async {
    if (_analysisService == null) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final result = await _analysisService!.analyzeImage(imageFile);
      
      setState(() {
        _lastResult = result;
        _imageResults[imageFile] = result; // เก็บผลการวิเคราะห์
        _isProcessing = false;
      });

      // แสดงการแจ้งเตือนถ้าพบเพลี้ยจำนวนมาก
      if (result.totalPests > 50) {
        _showAlertDialog(
          '⚠️ ตรวจพบเพลี้ยจำนวนมาก!',
          'พบเพลี้ยกระโดดสีน้ำตาล ${result.totalPests} ตัว\n'
          'ความหนาแน่น: ${result.density.toStringAsFixed(2)} ตัว/ตร.ม.\n'
          'แนะนำให้ใช้สารกำจัดแมลง',
        );
      } else if (result.totalPests > 20) {
        _showAlertDialog(
          '⚠️ ตรวจพบเพลี้ยปานกลาง',
          'พบเพลี้ยกระโดดสีน้ำตาล ${result.totalPests} ตัว\n'
          'ความหนาแน่น: ${result.density.toStringAsFixed(2)} ตัว/ตร.ม.\n'
          'ควรเฝ้าระวังและตรวจสอบอย่างสม่ำเสมอ',
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการวิเคราะห์: $e')),
        );
      }
    }
  }

  Future<void> _analyzeAllImages() async {
    if (_capturedImages.isEmpty || _analysisService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่มีรูปภาพให้วิเคราะห์')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      int totalPests = 0;
      for (var imageFile in _capturedImages) {
        final result = await _analysisService!.analyzeImage(imageFile);
        totalPests += result.totalPests;
      }

      // คำนวณความหนาแน่นเฉลี่ย (สมมติว่า 1 งาน = 400 ตร.ม.)
      final double averageDensity = totalPests / (400 * _capturedImages.length);

      setState(() {
        _isProcessing = false;
      });

      _showAlertDialog(
        '📊 ผลการวิเคราะห์ทั้งหมด',
        'จำนวนรูปที่วิเคราะห์: ${_capturedImages.length} รูป\n'
        'จำนวนเพลี้ยทั้งหมด: $totalPests ตัว\n'
        'ความหนาแน่นเฉลี่ย: ${averageDensity.toStringAsFixed(2)} ตัว/ตร.ม.\n'
        'ต่อ 1 งาน (400 ตร.ม.): ${(averageDensity * 400).toStringAsFixed(0)} ตัว',
        isWarning: averageDensity > 0.5,
      );
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

  void _showAlertDialog(String title, String message, {bool isWarning = false}) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isWarning
                  ? [Colors.orange.shade50, Colors.orange.shade100]
                  : [Colors.blue.shade50, Colors.blue.shade100],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isWarning ? Colors.orange.shade400 : Colors.blue.shade400,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isWarning ? Icons.warning_rounded : Icons.analytics_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isWarning ? Colors.orange.shade900 : Colors.blue.shade900,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade800,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isWarning ? Colors.orange.shade600 : Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'ตกลง',
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
      ),
    );
  }

  void _clearImages() {
    setState(() {
      _capturedImages.clear();
      _imageResults.clear();
      _lastResult = null;
    });
  }
  
  
  // ฟังก์ชันสำหรับดูรูปภาพพร้อม bounding boxes
  void _viewImageWithBoxes(File imageFile) {
    final result = _imageResults[imageFile];
    if (result == null) return;
    
    // อ่านขนาดรูปภาพจริง
    final imageBytes = imageFile.readAsBytesSync();
    final image = img.decodeImage(imageBytes);
    if (image == null) return;
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.orange.shade400, Colors.orange.shade600],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.bug_report, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'ผลการตรวจจับ',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: ImageWithBoxes(
                          imageFile: imageFile,
                          result: result,
                          displayWidth: MediaQuery.of(context).size.width - 80,
                          displayHeight: (MediaQuery.of(context).size.width - 80) * 
                                      (image.height / image.width),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // สถิติ
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: result.totalPests > 50
                                ? [Colors.red.shade50, Colors.red.shade100]
                                : result.totalPests > 20
                                    ? [Colors.orange.shade50, Colors.orange.shade100]
                                    : [Colors.green.shade50, Colors.green.shade100],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: (result.totalPests > 50
                                    ? Colors.red
                                    : result.totalPests > 20
                                        ? Colors.orange
                                        : Colors.green)
                                .shade200,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.analytics_rounded,
                                  size: 24,
                                  color: (result.totalPests > 50
                                          ? Colors.red
                                          : result.totalPests > 20
                                              ? Colors.orange
                                              : Colors.green)
                                      .shade700,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'สรุปผลการวิเคราะห์',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: (result.totalPests > 50
                                            ? Colors.red
                                            : result.totalPests > 20
                                                ? Colors.orange
                                                : Colors.green)
                                        .shade800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildStatCard(
                              Icons.bug_report,
                              'พบเพลี้ย',
                              '${result.totalPests} ตัว',
                              Colors.orange,
                            ),
                            const SizedBox(height: 12),
                            _buildStatCard(
                              Icons.area_chart,
                              'ความหนาแน่น',
                              '${result.density.toStringAsFixed(2)} ตัว/ตร.ม.',
                              Colors.blue,
                            ),
                            const SizedBox(height: 12),
                            _buildStatCard(
                              Icons.visibility,
                              'จำนวน detections',
                              '${result.detections.length}',
                              Colors.purple,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Actions
              Container(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'ปิด',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getColorShade(Color color, int shade) {
    if (color == Colors.red) {
      return Colors.red.shade700;
    } else if (color == Colors.green) {
      return Colors.green.shade700;
    } else if (color == Colors.blue) {
      return Colors.blue.shade700;
    } else if (color == Colors.orange) {
      return Colors.orange.shade700;
    } else if (color == Colors.purple) {
      return Colors.purple.shade700;
    }
    return color;
  }

  Widget _buildStatCard(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _getColorShade(color, 700),
                  ),
                ),
              ],
            ),
          ),
        ],
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
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.bug_report, size: 24),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'วิเคราะห์เพลี้ย',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  'ถ่ายรูปและนับจำนวน',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
        ),
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.orange.shade400, Colors.orange.shade600],
            ),
          ),
        ),
        actions: [
          if (_capturedImages.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: const Icon(Icons.delete_sweep),
                onPressed: _clearImages,
                tooltip: 'ลบรูปทั้งหมด',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // กล้อง
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                _isInitialized && _controller != null
                    ? CameraPreview(_controller!)
                    : Container(
                        color: Colors.black,
                        child: const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ),
                // Overlay guide
                if (_isInitialized && _controller != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 2,
                          ),
                        ),
                        margin: const EdgeInsets.all(40),
                      ),
                    ),
                  ),
                // Loading overlay
                if (_isProcessing)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.5),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'กำลังวิเคราะห์...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // ผลการวิเคราะห์
          if (_lastResult != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _lastResult!.totalPests > 50
                      ? [Colors.red.shade400, Colors.red.shade600]
                      : _lastResult!.totalPests > 20
                          ? [Colors.orange.shade400, Colors.orange.shade600]
                          : [Colors.green.shade400, Colors.green.shade600],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: (_lastResult!.totalPests > 50
                            ? Colors.red
                            : _lastResult!.totalPests > 20
                                ? Colors.orange
                                : Colors.green)
                        .withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _lastResult!.totalPests > 50
                          ? Icons.warning_rounded
                          : Icons.check_circle_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'พบเพลี้ย ${_lastResult!.totalPests} ตัว',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.area_chart,
                              size: 16,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'ความหนาแน่น: ${_lastResult!.density.toStringAsFixed(2)} ตัว/ตร.ม.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withValues(alpha: 0.95),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          // รูปที่ถ่าย
          if (_capturedImages.isNotEmpty)
            Container(
              height: 110,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200, width: 1),
                  bottom: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.photo_library, size: 18, color: Colors.grey.shade700),
                        const SizedBox(width: 6),
                        Text(
                          'รูปที่ถ่าย (${_capturedImages.length})',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _capturedImages.length,
                      itemBuilder: (context, index) {
                        final imageFile = _capturedImages[index];
                        final result = _imageResults[imageFile];
                        return GestureDetector(
                          onTap: () => _viewImageWithBoxes(imageFile),
                          child: Container(
                            margin: const EdgeInsets.only(right: 12),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.2),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Image.file(
                                      imageFile,
                                      width: 85,
                                      height: 85,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                if (result != null && result.detections.isNotEmpty)
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [Colors.red.shade400, Colors.red.shade600],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.red.withValues(alpha: 0.5),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.bug_report,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${result.totalPests}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          // ปุ่มควบคุม
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ปุ่มควบคุม
                Row(
                  children: [
                    // ปุ่มถ่ายรูป
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _isProcessing ? null : _takePicture,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: _isProcessing
                                    ? [Colors.grey.shade400, Colors.grey.shade500]
                                    : [Colors.blue.shade400, Colors.blue.shade600],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: _isProcessing
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: Colors.blue.withValues(alpha: 0.4),
                                        blurRadius: 12,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.camera_alt_rounded,
                                  size: 26,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'ถ่ายรูป',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // ปุ่มวิเคราะห์ทั้งหมด
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _isProcessing || _capturedImages.isEmpty
                              ? null
                              : _analyzeAllImages,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: (_isProcessing || _capturedImages.isEmpty)
                                    ? [Colors.grey.shade400, Colors.grey.shade500]
                                    : [Colors.green.shade400, Colors.green.shade600],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: (_isProcessing || _capturedImages.isEmpty)
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: Colors.green.withValues(alpha: 0.4),
                                        blurRadius: 12,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_isProcessing)
                                  const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.analytics_rounded,
                                    size: 26,
                                    color: Colors.white,
                                  ),
                                const SizedBox(width: 10),
                                Text(
                                  _isProcessing ? 'กำลังวิเคราะห์...' : 'วิเคราะห์ทั้งหมด',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

