import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../models/pest_result.dart';

class ImageWithBoxes extends StatelessWidget {
  final File imageFile;
  final PestResult? result;
  final double displayWidth;
  final double displayHeight;

  const ImageWithBoxes({
    super.key,
    required this.imageFile,
    this.result,
    required this.displayWidth,
    required this.displayHeight,
  });

  @override
  Widget build(BuildContext context) {
    // อ่านขนาดรูปภาพจริง
    final imageBytes = imageFile.readAsBytesSync();
    final image = img.decodeImage(imageBytes);
    final originalWidth = image?.width ?? 1.0;
    final originalHeight = image?.height ?? 1.0;
    
    // คำนวณ scale factor
    final scaleX = displayWidth / originalWidth;
    final scaleY = displayHeight / originalHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY; // ใช้ scale ที่เล็กกว่าเพื่อ maintain aspect ratio
    
    // คำนวณขนาดรูปที่แสดงจริง (อาจมี letterbox)
    final actualDisplayWidth = originalWidth * scale;
    final actualDisplayHeight = originalHeight * scale;
    final offsetX = (displayWidth - actualDisplayWidth) / 2;
    final offsetY = (displayHeight - actualDisplayHeight) / 2;
    
    return Stack(
      children: [
        // รูปภาพ
        Center(
          child: Image.file(
            imageFile,
            width: actualDisplayWidth,
            height: actualDisplayHeight,
            fit: BoxFit.contain,
          ),
        ),
        // Bounding boxes
        if (result != null && result!.detections.isNotEmpty)
          Positioned(
            left: offsetX,
            top: offsetY,
            child: CustomPaint(
              size: Size(actualDisplayWidth, actualDisplayHeight),
              painter: BoundingBoxPainter(
                detections: result!.detections,
                scale: scale,
              ),
            ),
          ),
      ],
    );
  }
}

class BoundingBoxPainter extends CustomPainter {
  final List<PestDetection> detections;
  final double scale;

  BoundingBoxPainter({
    required this.detections,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (final detection in detections) {
      // Scale bounding box coordinates
      final x = detection.x * scale;
      final y = detection.y * scale;
      final w = detection.width * scale;
      final h = detection.height * scale;
      
      // วาดสี่เหลี่ยม
      final rect = Rect.fromLTWH(x, y, w, h);
      canvas.drawRect(rect, paint);

      // วาดข้อความ confidence
      final confidenceText = '${(detection.confidence * 100).toStringAsFixed(1)}%';
      textPainter.text = TextSpan(
        text: confidenceText,
        style: const TextStyle(
          color: Colors.red,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.white,
        ),
      );
      textPainter.layout();
      
      // วาด background สำหรับข้อความ
      final textRect = Rect.fromLTWH(
        x,
        y - 20,
        textPainter.width + 4,
        textPainter.height + 4,
      );
      canvas.drawRect(
        textRect,
        Paint()..color = Colors.white,
      );
      
      textPainter.paint(
        canvas,
        Offset(x + 2, y - 18),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

