import 'dart:io';
import 'package:flutter/material.dart';
import '../models/pest_result.dart';
import 'pest_info_screen.dart';

class ScanDetailsScreen extends StatelessWidget {
  final File imageFile;
  final PestResult result;
  final DateTime scanTime;

  const ScanDetailsScreen({
    super.key,
    required this.imageFile,
    required this.result,
    required this.scanTime,
  });

  String _getRiskLevel() {
    if (result.totalPests > 50) return 'เสี่ยงสูง';
    if (result.totalPests > 20) return 'เสี่ยงปานกลาง';
    if (result.totalPests > 0) return 'เสี่ยงต่ำ';
    return 'ปลอดภัย';
  }

  Color _getRiskColor() {
    if (result.totalPests > 50) return const Color(0xFFF44336);
    if (result.totalPests > 20) return const Color(0xFFFF9800);
    if (result.totalPests > 0) return const Color(0xFFFFC107);
    return const Color(0xFF4CAF50);
  }

  String _getPestName() {
    if (result.detections.isEmpty) return 'ไม่พบเพลี้ย';
    // Get the most common pest type
    final pestTypes = <String, int>{};
    for (final detection in result.detections) {
      pestTypes[detection.label] = (pestTypes[detection.label] ?? 0) + 1;
    }
    final mostCommon = pestTypes.entries.reduce((a, b) => a.value > b.value ? a : b);
    return mostCommon.key;
  }

  String _getRecommendation() {
    if (result.totalPests > 50) {
      return 'ตรวจพบการระบาดรุนแรงที่โคนต้นข้าว\n\nคำแนะนำ: ใช้สาร Buprofezin (เช่น Applaud 25% WP) อัตรา 20 กรัม/น้ำ 16 ลิตร ฉีดพ่นที่โคนต้น\n\nติดตามผลทุกวัน และฉีดซ้ำหากจำเป็นหลัง 7-10 วัน\n\nสวมอุปกรณ์ป้องกันขณะฉีดพ่น';
    } else if (result.totalPests > 20) {
      return 'ตรวจพบเพลี้ยในระดับปานกลาง\n\nคำแนะนำ: เฝ้าระวังอย่างใกล้ชิดและพิจารณาใช้วิธีควบคุมทางชีวภาพ เช่น ศัตรูธรรมชาติ\n\nหลีกเลี่ยงการใช้สารเคมีมากเกินไปเพื่อรักษาแมลงที่เป็นประโยชน์';
    } else if (result.totalPests > 0) {
      return 'ตรวจพบเพลี้ยในระดับต่ำ\n\nคำแนะนำ: ตรวจสอบอย่างสม่ำเสมอ\n\nรักษาความสะอาดของแปลงและหลีกเลี่ยงการใส่ปุ๋ยไนโตรเจนมากเกินไป';
    }
    return 'ไม่พบการระบาดของเพลี้ย\n\nต้นข้าวของคุณดูสุขภาพดี ให้ตรวจสอบและดูแลตามปกติต่อไป';
  }

  @override
  Widget build(BuildContext context) {
    final riskLevel = _getRiskLevel();
    final riskColor = _getRiskColor();
    final pestName = _getPestName();

    return Scaffold(
      backgroundColor: const Color(0xFFE8F5E9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF2E7D32)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'รายละเอียดการสแกน',
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
            // Image Card
            Center(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.file(
                    imageFile,
                    width: 280,
                    height: 200,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Date and Time
            Center(
              child: Text(
                _formatDateTime(scanTime),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Risk Badge
            Center(
              child: GestureDetector(
                onTap: result.totalPests > 0
                    ? () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PestInfoScreen(
                              pestName: pestName,
                              pestCount: result.totalPests,
                              riskLevel: riskLevel,
                            ),
                          ),
                        );
                      }
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: riskColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$riskLevel: $pestName',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      if (result.totalPests > 0) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.white,
                          size: 14,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Detection Stats
            if (result.totalPests > 0)
              Container(
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(
                      'พบเพลี้ย',
                      '${result.totalPests}',
                      Icons.bug_report,
                      riskColor,
                    ),
                    Container(
                      height: 40,
                      width: 1,
                      color: Colors.grey.shade200,
                    ),
                    _buildStatItem(
                      'ความหนาแน่น',
                      '${result.density.toStringAsFixed(1)}/ตร.ม.',
                      Icons.grid_4x4,
                      Colors.blue,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),

            // Notes Section
            const Text(
              'บันทึก',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2E7D32),
              ),
            ),
            const SizedBox(height: 12),
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
              child: Text(
                _getRecommendation(),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Action Button
            if (result.totalPests > 0)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PestInfoScreen(
                          pestName: pestName,
                          pestCount: result.totalPests,
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
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final thaiMonths = [
      'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
      'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'
    ];
    return '${dateTime.day} ${thaiMonths[dateTime.month - 1]} ${dateTime.year + 543}, ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')} น.';
  }
}
