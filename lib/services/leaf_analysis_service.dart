import 'dart:io';
import 'package:image/image.dart' as img;
import '../screens/leaf_analysis_screen.dart';

class LeafAnalysisService {
  // มาตรฐานสีเขียวของใบข้าว (ค่าเฉลี่ยสีเขียวที่เหมาะสม)
  // ค่า G (Green) ควรอยู่ที่ประมาณ 100-150 สำหรับใบข้าวที่เขียวดี
  static const double standardGreenMin = 100.0;
  static const double standardGreenMax = 200.0;

  Future<LeafAnalysisResult> analyzeLeafColor(File imageFile) async {
    // อ่านภาพ
    final imageBytes = await imageFile.readAsBytes();
    final image = img.decodeImage(imageBytes);

    if (image == null) {
      throw Exception('ไม่สามารถอ่านภาพได้');
    }

    // คำนวณค่าเฉลี่ยสี RGB
    int totalR = 0;
    int totalG = 0;
    int totalB = 0;
    int pixelCount = 0;

    // วิเคราะห์เฉพาะส่วนกลางของภาพ (สมมติว่าใบข้าวอยู่ตรงกลาง)
    final centerX = image.width ~/ 2;
    final centerY = image.height ~/ 2;
    final sampleSize = (image.width * 0.3).toInt(); // ใช้ 30% ของภาพ

    for (int y = centerY - sampleSize ~/ 2; 
         y < centerY + sampleSize ~/ 2 && y < image.height; 
         y++) {
      if (y < 0) continue;
      for (int x = centerX - sampleSize ~/ 2; 
           x < centerX + sampleSize ~/ 2 && x < image.width; 
           x++) {
        if (x < 0) continue;
        final pixel = image.getPixel(x, y);
        totalR += pixel.r.toInt();
        totalG += pixel.g.toInt();
        totalB += pixel.b.toInt();
        pixelCount++;
      }
    }

    if (pixelCount == 0) {
      throw Exception('ไม่สามารถวิเคราะห์ภาพได้');
    }

    final averageR = totalR ~/ pixelCount;
    final averageG = totalG ~/ pixelCount;
    final averageB = totalB ~/ pixelCount;

    // คำนวณค่าเฉลี่ยสีเขียว (ใช้ค่า G เป็นหลัก)
    final averageGreen = averageG.toDouble();

    // กำหนดมาตรฐานสีเขียว (ค่าเฉลี่ยระหว่าง min และ max)
    const greenStandard = (standardGreenMin + standardGreenMax) / 2;

    // ตรวจสอบว่าเขียวตามมาตรฐานหรือไม่
    // ถ้าค่า G อยู่ในช่วงมาตรฐาน ถือว่าเขียวดี
    final isHealthy = averageGreen >= standardGreenMin && 
                     averageGreen <= standardGreenMax;

    return LeafAnalysisResult(
      averageR: averageR,
      averageG: averageG,
      averageB: averageB,
      averageGreen: averageGreen,
      greenStandard: greenStandard,
      isHealthy: isHealthy,
    );
  }
}

