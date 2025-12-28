import 'dart:io';
import 'package:flutter/material.dart';
import '../models/pest_result.dart';
import 'pest_info_screen.dart';

class AnalysisSummaryScreen extends StatelessWidget {
  final List<File> capturedImages;
  final Map<File, PestResult> imageResults;
  final int totalPests;
  final int areaSize;
  final double density;

  const AnalysisSummaryScreen({
    super.key,
    required this.capturedImages,
    required this.imageResults,
    required this.totalPests,
    required this.areaSize,
    required this.density,
  });

  String _getRiskLevel() {
    // ความหนาแน่นต่อตารางเมตร
    if (density > 10) return 'เสี่ยงสูงมาก';
    if (density > 5) return 'เสี่ยงสูง';
    if (density > 2) return 'เสี่ยงปานกลาง';
    if (density > 0) return 'เสี่ยงต่ำ';
    return 'ปลอดภัย';
  }

  Color _getRiskColor() {
    if (density > 10) return const Color(0xFFB71C1C);
    if (density > 5) return const Color(0xFFF44336);
    if (density > 2) return const Color(0xFFFF9800);
    if (density > 0) return const Color(0xFFFFC107);
    return const Color(0xFF4CAF50);
  }

  IconData _getRiskIcon() {
    if (density > 5) return Icons.warning_rounded;
    if (density > 2) return Icons.error_outline;
    if (density > 0) return Icons.info_outline;
    return Icons.check_circle;
  }

  String _getRecommendation() {
    if (density > 10) {
      return 'พบการระบาดรุนแรงมาก! ต้องใช้สารกำจัดแมลงทันที\n\nแนะนำ: Buprofezin อัตรา 20g/16L ฉีดพ่นทั่วแปลง';
    } else if (density > 5) {
      return 'พบการระบาดรุนแรง ควรใช้สารกำจัดแมลง\n\nแนะนำ: Buprofezin อัตรา 20g/16L ฉีดที่โคนต้น';
    } else if (density > 2) {
      return 'พบเพลี้ยในระดับปานกลาง ควรเฝ้าระวังและตรวจสอบบ่อยๆ\n\nอาจพิจารณาใช้วิธีควบคุมทางชีวภาพ';
    } else if (density > 0) {
      return 'พบเพลี้ยในระดับต่ำ ไม่ต้องใช้สารเคมี\n\nให้ตรวจสอบสม่ำเสมอและรักษาความสะอาดแปลง';
    }
    return 'ไม่พบเพลี้ยในแปลง ต้นข้าวสุขภาพดี!\n\nให้ดูแลและตรวจสอบตามปกติ';
  }

  @override
  Widget build(BuildContext context) {
    final riskLevel = _getRiskLevel();
    final riskColor = _getRiskColor();
    final riskIcon = _getRiskIcon();
    final areaInSquareMeters = areaSize * 4; // 1 ตารางวา = 4 ตารางเมตร

    return Scaffold(
      backgroundColor: const Color(0xFFE8F5E9),
      appBar: AppBar(
        backgroundColor: riskColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () {
            Navigator.popUntil(context, (route) => route.isFirst);
          },
        ),
        title: const Text(
          'ผลการวิเคราะห์',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Risk Level Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: riskColor,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      riskIcon,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    riskLevel,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'พื้นที่ $areaSize ตารางวา ($areaInSquareMeters ตร.ม.)',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats Cards
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'พบเพลี้ยทั้งหมด',
                          '$totalPests',
                          'ตัว',
                          Icons.bug_report,
                          riskColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          'ความหนาแน่น',
                          density.toStringAsFixed(1),
                          'ตัว/ตร.ม.',
                          Icons.grid_4x4,
                          Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'จำนวนรูป',
                          '${capturedImages.length}',
                          'รูป',
                          Icons.camera_alt,
                          Colors.purple,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          'เฉลี่ยต่อรูป',
                          capturedImages.isNotEmpty 
                              ? (totalPests / capturedImages.length).toStringAsFixed(1)
                              : '0',
                          'ตัว',
                          Icons.calculate,
                          Colors.teal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Recommendation Card
                  const Text(
                    'คำแนะนำ',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: riskColor.withValues(alpha: 0.3),
                        width: 2,
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
                            Icon(riskIcon, color: riskColor, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                riskLevel,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: riskColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _getRecommendation(),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Captured Images
                  const Text(
                    'รูปที่ถ่าย',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: capturedImages.length,
                      itemBuilder: (context, index) {
                        final imageFile = capturedImages[index];
                        final result = imageResults[imageFile];
                        return Container(
                          margin: const EdgeInsets.only(right: 12),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  imageFile,
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              if (result != null)
                                Positioned(
                                  bottom: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: result.totalPests > 0
                                          ? Colors.red
                                          : Colors.green,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${result.totalPests}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  if (totalPests > 0)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PestInfoScreen(
                                pestName: 'เพลี้ยกระโดดสีน้ำตาล',
                                pestCount: totalPests,
                                riskLevel: riskLevel,
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: riskColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'ดูวิธีการรักษา',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.popUntil(context, (route) => route.isFirst);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF2E7D32),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(
                          color: Color(0xFF4CAF50),
                          width: 2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'กลับหน้าหลัก',
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
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    String unit,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
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
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            unit,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}


