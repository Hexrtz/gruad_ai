import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import '../models/pest_result.dart';

class PestAnalysisService {
  final Interpreter interpreter;
  static const int inputSize = 640; // YOLOv8 input size
  static const double confidenceThreshold = 0.2; // ลด threshold ลงเพื่อให้ตรวจจับได้มากขึ้น
  static const double classConfidenceThreshold = 0.15; // threshold สำหรับ class confidence
  static const double objectnessThreshold = 0.15; // threshold สำหรับ objectness
  static const double nmsThreshold = 0.45; // NMS threshold
  static const double minBoxSize = 0.01; // ลดขนาดขั้นต่ำ (1% ของภาพ)
  static const double maxBoxSize = 0.95; // ขนาด bounding box สูงสุด (95% ของภาพ)
  static const int numClasses = 6; // จำนวน classes จาก metadata.yaml

  List<String>? _classLabels;
  
  PestAnalysisService(this.interpreter) {
    _loadLabels();
  }

  Future<void> _loadLabels() async {
    try {
      final String labelsString = await rootBundle.loadString('assets/labels.txt');
      _classLabels = labelsString
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      debugPrint('Loaded ${_classLabels!.length} class labels: $_classLabels');
    } catch (e) {
      debugPrint('Failed to load labels.txt: $e');
      // Fallback to default labels
      _classLabels = [
        'brown-planthopper',
        'green-leafhopper',
        'leaf-folder',
        'rice-bug',
        'stem-borer',
        'whorl-maggot',
      ];
    }
  }

  String _getLabel(int classIndex) {
    if (_classLabels != null && classIndex >= 0 && classIndex < _classLabels!.length) {
      return _classLabels![classIndex];
    }
    return 'pest_$classIndex';
  }

  Future<PestResult> analyzeImage(File imageFile) async {
    // อ่านและประมวลผลภาพ
    final imageBytes = await imageFile.readAsBytes();
    final image = img.decodeImage(imageBytes);
    
    if (image == null) {
      throw Exception('ไม่สามารถอ่านภาพได้');
    }

    // ปรับขนาดภาพให้เป็น 640x640
    final resizedImage = img.copyResize(
      image,
      width: inputSize,
      height: inputSize,
    );

    // แปลงเป็น input tensor
    final input = _imageToByteListFloat32(resizedImage, inputSize);

    // ตรวจสอบ output shape จาก interpreter
    final outputTensor = interpreter.getOutputTensor(0);
    final outputShape = outputTensor.shape;
    
    debugPrint('Output shape: $outputShape');
    
    // สร้าง output buffer ที่ตรงกับ shape
    // YOLOv8 อาจมี output shape เป็น [1, 10, 8400] หรือ [1, 8400, 84]
    dynamic output;
    if (outputShape.length == 3) {
      // Shape: [batch, rows, cols]
      output = List.generate(
        outputShape[0],
        (_) => List.generate(
          outputShape[1],
          (_) => List.generate(
            outputShape[2],
            (_) => 0.0,
          ),
        ),
      );
    } else if (outputShape.length == 2) {
      // Shape: [rows, cols]
      output = List.generate(
        outputShape[0],
        (_) => List.generate(
          outputShape[1],
          (_) => 0.0,
        ),
      );
    } else {
      // Flat list
      output = List.generate(
        outputShape.reduce((a, b) => a * b),
        (_) => 0.0,
      );
    }

    // รัน inference
    interpreter.run(input, output);

    // ประมวลผลผลลัพธ์
    var detections = _processOutput(output, outputShape, image.width, image.height);
    
    debugPrint('Before NMS: ${detections.length} detections');
    
    // ใช้ Non-Maximum Suppression เพื่อลบ duplicate detections
    detections = _applyNMS(detections);
    
    debugPrint('After NMS: ${detections.length} detections');
    debugPrint('Detections summary:');
    for (int i = 0; i < detections.length && i < 5; i++) {
      final d = detections[i];
      debugPrint('  Detection $i: conf=${d.confidence.toStringAsFixed(3)}, bbox=[${d.x.toStringAsFixed(1)}, ${d.y.toStringAsFixed(1)}, ${d.width.toStringAsFixed(1)}, ${d.height.toStringAsFixed(1)}]');
    }

    // คำนวณความหนาแน่น (สมมติว่า 1 ตร.ม. = 100x100 pixels)
    final double areaInSquareMeters = (image.width * image.height) / 10000.0;
    final double density = detections.length / areaInSquareMeters;

    return PestResult(
      totalPests: detections.length,
      density: density,
      detections: detections,
    );
  }

  List<PestDetection> _processOutput(
    dynamic output,
    List<int> outputShape,
    int originalWidth,
    int originalHeight,
  ) {
    final List<PestDetection> detections = [];

    // YOLOv8 output format อาจเป็น:
    // [1, 10, 8400] - 10 detections, แต่ละ detection มี 8400 values
    // [1, 8400, 84] - 8400 detections, แต่ละ detection มี 84 values (4 bbox + 80 classes)
    
    if (outputShape.length == 3) {
      // Shape: [batch, num_detections, features]
      final numDetections = outputShape[1];
      final features = outputShape[2];
      
      // สำหรับ [1, 10, 8400] - อาจเป็น format พิเศษ
      // สำหรับ [1, 8400, 84] - standard YOLOv8 format
      
      if (features == 84) {
        // Standard YOLOv8 format: [1, 8400, 84]
        for (int i = 0; i < numDetections; i++) {
          final detection = output[0][i] as List;
          
          // อ่าน bounding box (x_center, y_center, width, height) - normalized
          final xCenter = detection[0] as double;
          final yCenter = detection[1] as double;
          final width = detection[2] as double;
          final height = detection[3] as double;
          
          // หา class ที่มี confidence สูงสุด (index 4-83)
          double maxConfidence = 0.0;
          int bestClass = 0;
          
          for (int j = 4; j < 84; j++) {
            final confidence = detection[j] as double;
            if (confidence > maxConfidence) {
              maxConfidence = confidence;
              bestClass = j - 4;
            }
          }

          if (maxConfidence < confidenceThreshold) {
            continue;
          }

          // แปลงเป็นพิกัดจริง (pixels)
          final x = (xCenter - width / 2) * originalWidth;
          final y = (yCenter - height / 2) * originalHeight;
          final w = width * originalWidth;
          final h = height * originalHeight;

          detections.add(PestDetection(
            x: x,
            y: y,
            width: w,
            height: h,
            confidence: maxConfidence,
            label: _getLabel(bestClass),
          ));
        }
      } else if ((numDetections == 10 || numDetections == 11) && features == 8400) {
        // Format: [1, 10, 8400] หรือ [1, 11, 8400] - สำหรับ YOLOv8 ที่ fine-tune
        // นี่หมายถึง 10 หรือ 11 output channels แต่ละ channel มี 8400 detections
        // Structure: [x, y, w, h, objectness, class1, class2, ...]
        // 10 channels = 4 bbox + 1 objectness + 5 classes
        // 11 channels = 4 bbox + 1 objectness + 6 classes
        debugPrint('Processing format [1, $numDetections, 8400] - $numDetections channels format');
        
        // ตรวจสอบจำนวน classes ที่มีจริง
        final int actualNumClasses = numDetections - 5; // ลบ 4 bbox + 1 objectness
        debugPrint('Detected $actualNumClasses classes from output shape (channels: 0-3=bbox, 4=objectness, 5-${numDetections-1}=classes)');
        
        for (int i = 0; i < 8400; i++) {
          // อ่านค่าจากแต่ละ channel (10 channels: 0-9)
          final xCenter = (output[0][0][i] as double);
          final yCenter = (output[0][1][i] as double);
          final width = (output[0][2][i] as double);
          final height = (output[0][3][i] as double);
          final objectness = (output[0][4][i] as double);
          
          // หา class confidence สูงสุด (index 5-9 สำหรับ 5 classes)
          double maxClassConfidence = 0.0;
          int bestClass = 0;
          
          // อ่าน class confidence จาก index 5 ถึง 9 (5 classes)
          for (int j = 5; j < numDetections; j++) {
            final classConf = (output[0][j][i] as double);
            if (classConf > maxClassConfidence) {
              maxClassConfidence = classConf;
              bestClass = j - 5;
            }
          }
          
          // คำนวณ confidence สำหรับ fine-tuned model
          // ใช้ max ของ (objectness * class_confidence, class_confidence, objectness) เพื่อความแม่นยำ
          double confidence;
          if (maxClassConfidence > 0) {
            // ใช้ max ของ objectness * class_confidence, class_confidence, และ objectness
            final conf1 = objectness * maxClassConfidence;
            final conf2 = maxClassConfidence;
            final conf3 = objectness;
            confidence = conf1 > conf2 ? (conf1 > conf3 ? conf1 : conf3) : (conf2 > conf3 ? conf2 : conf3);
          } else {
            // ถ้าไม่มี class confidence ให้ใช้ objectness
            confidence = objectness;
          }
          
          // Debug logging สำหรับ detections ทั้งหมดที่ผ่านการกรองเบื้องต้น
          if (objectness > 0.1 || maxClassConfidence > 0.1 || confidence > 0.1) {
            debugPrint('Detection $i: objectness=${objectness.toStringAsFixed(3)}, classConf=${maxClassConfidence.toStringAsFixed(3)}, finalConf=${confidence.toStringAsFixed(3)}, class=$bestClass, bbox=[${xCenter.toStringAsFixed(3)}, ${yCenter.toStringAsFixed(3)}, ${width.toStringAsFixed(3)}, ${height.toStringAsFixed(3)}]');
          }
          
          // กรอง detections ที่มี confidence ต่ำสุด
          if (confidence < confidenceThreshold) {
            continue;
          }
          
          // ตรวจสอบ objectness และ class confidence (ต้องมีอย่างน้อย 1 ตัวที่ผ่าน threshold)
          final hasValidObjectness = objectness >= objectnessThreshold;
          final hasValidClassConf = maxClassConfidence >= classConfidenceThreshold;
          
          if (!hasValidObjectness && !hasValidClassConf) {
            debugPrint('  -> Filtered: both objectness (${objectness.toStringAsFixed(3)}) and classConf (${maxClassConfidence.toStringAsFixed(3)}) below thresholds');
            continue;
          }
          
          // ตรวจสอบขนาด bounding box (กรอง detections ที่เล็กหรือใหญ่เกินไป)
          if (width < minBoxSize || height < minBoxSize || width > maxBoxSize || height > maxBoxSize) {
            debugPrint('Filtered detection $i: box size too small/large: [$width, $height]');
            continue;
          }
          
          // ตรวจสอบว่าอยู่ในขอบเขตภาพ (ให้ margin เล็กน้อย)
          if (xCenter < -0.1 || xCenter > 1.1 || yCenter < -0.1 || yCenter > 1.1) {
            debugPrint('Filtered detection $i: out of bounds: [$xCenter, $yCenter]');
            continue;
          }
          
          // ตรวจสอบว่า bounding box อยู่ในขอบเขตภาพ
          final boxLeft = xCenter - width / 2;
          final boxTop = yCenter - height / 2;
          final boxRight = xCenter + width / 2;
          final boxBottom = yCenter + height / 2;
          
          if (boxRight < 0 || boxLeft > 1 || boxBottom < 0 || boxTop > 1) {
            debugPrint('Filtered detection $i: box completely out of bounds');
            continue;
          }

          // แปลงเป็นพิกัดจริง (pixels) - YOLOv8 ใช้ normalized coordinates
          final x = (xCenter - width / 2) * originalWidth;
          final y = (yCenter - height / 2) * originalHeight;
          final w = width * originalWidth;
          final h = height * originalHeight;

          detections.add(PestDetection(
            x: x,
            y: y,
            width: w,
            height: h,
            confidence: confidence,
            label: _getLabel(bestClass),
          ));
        }
        
        debugPrint('Found ${detections.length} detections before NMS (confidenceThreshold: $confidenceThreshold, classConfThreshold: $classConfidenceThreshold, objectnessThreshold: $objectnessThreshold)');
      }
    } else if (outputShape.length == 2) {
      // Shape: [rows, cols]
      final rows = outputShape[0];
      final cols = outputShape[1];
      
      if (cols == 84) {
        // Format: [8400, 84]
        for (int i = 0; i < rows; i++) {
          final detection = output[i] as List;
          
          final xCenter = detection[0] as double;
          final yCenter = detection[1] as double;
          final width = detection[2] as double;
          final height = detection[3] as double;
          
          double maxConfidence = 0.0;
          int bestClass = 0;
          
          for (int j = 4; j < 84; j++) {
            final confidence = detection[j] as double;
            if (confidence > maxConfidence) {
              maxConfidence = confidence;
              bestClass = j - 4;
            }
          }

          if (maxConfidence < confidenceThreshold) {
            continue;
          }

          final x = (xCenter - width / 2) * originalWidth;
          final y = (yCenter - height / 2) * originalHeight;
          final w = width * originalWidth;
          final h = height * originalHeight;

          detections.add(PestDetection(
            x: x,
            y: y,
            width: w,
            height: h,
            confidence: maxConfidence,
            label: _getLabel(bestClass),
          ));
        }
      }
    } else if (output is List<double>) {
      // Flat list - แปลงเป็น nested structure
      // สมมติว่าเป็น [8400, 84] format
      final totalElements = output.length;
      final numDetections = totalElements ~/ 84;
      
      for (int i = 0; i < numDetections; i++) {
        final startIndex = i * 84;
        
        final xCenter = output[startIndex];
        final yCenter = output[startIndex + 1];
        final width = output[startIndex + 2];
        final height = output[startIndex + 3];
        
        double maxConfidence = 0.0;
        int bestClass = 0;
        
        for (int j = 4; j < 84; j++) {
          final confidence = output[startIndex + j];
          if (confidence > maxConfidence) {
            maxConfidence = confidence;
            bestClass = j - 4;
          }
        }

        if (maxConfidence < confidenceThreshold) {
          continue;
        }

        final x = (xCenter - width / 2) * originalWidth;
        final y = (yCenter - height / 2) * originalHeight;
        final w = width * originalWidth;
        final h = height * originalHeight;

        detections.add(PestDetection(
          x: x,
          y: y,
          width: w,
          height: h,
          confidence: maxConfidence,
          label: _getLabel(bestClass),
        ));
      }
    }

    return detections;
  }

  // Non-Maximum Suppression เพื่อลบ duplicate detections
  List<PestDetection> _applyNMS(List<PestDetection> detections) {
    if (detections.isEmpty) return detections;

    // เรียงตาม confidence จากมากไปน้อย
    detections.sort((a, b) => b.confidence.compareTo(a.confidence));

    final List<PestDetection> filtered = [];
    final List<bool> suppressed = List.filled(detections.length, false);

    for (int i = 0; i < detections.length; i++) {
      if (suppressed[i]) continue;

      filtered.add(detections[i]);

      // คำนวณ IoU (Intersection over Union) กับ detections อื่นๆ
      for (int j = i + 1; j < detections.length; j++) {
        if (suppressed[j]) continue;

        final iou = _calculateIoU(detections[i], detections[j]);
        
        // ถ้า IoU สูงมาก (overlap มาก) ให้ suppress detection ที่ confidence ต่ำกว่า
        if (iou > nmsThreshold) {
          // ถ้า confidence ของ detection ที่สองต่ำกว่า 70% ของ detection แรก ให้ suppress
          // หรือถ้า IoU สูงมาก (>0.7) ให้ suppress ทันที
          if (iou > 0.7 || detections[j].confidence < detections[i].confidence * 0.7) {
            suppressed[j] = true;
            debugPrint('NMS suppressed: IoU=$iou, conf1=${detections[i].confidence}, conf2=${detections[j].confidence}');
          }
        }
      }
    }

    debugPrint('NMS: ${detections.length} -> ${filtered.length} detections (threshold: $nmsThreshold)');
    return filtered;
  }

  // คำนวณ IoU (Intersection over Union) ระหว่าง 2 bounding boxes
  double _calculateIoU(PestDetection box1, PestDetection box2) {
    final x1 = box1.x;
    final y1 = box1.y;
    final w1 = box1.width;
    final h1 = box1.height;
    final x2 = box2.x;
    final y2 = box2.y;
    final w2 = box2.width;
    final h2 = box2.height;

    // คำนวณ intersection
    final left = x1 > x2 ? x1 : x2;
    final top = y1 > y2 ? y1 : y2;
    final right = (x1 + w1) < (x2 + w2) ? (x1 + w1) : (x2 + w2);
    final bottom = (y1 + h1) < (y2 + h2) ? (y1 + h1) : (y2 + h2);

    if (right < left || bottom < top) {
      return 0.0;
    }

    final intersection = (right - left) * (bottom - top);
    final area1 = w1 * h1;
    final area2 = w2 * h2;
    final union = area1 + area2 - intersection;

    if (union <= 0) return 0.0;

    return intersection / union;
  }

  Uint8List _imageToByteListFloat32(img.Image image, int inputSize) {
    final convertedBytes = Float32List(1 * inputSize * inputSize * 3);
    final buffer = Float32List.view(convertedBytes.buffer);

    int pixelIndex = 0;
    for (int i = 0; i < inputSize; i++) {
      for (int j = 0; j < inputSize; j++) {
        final pixel = image.getPixel(j, i);
        // แปลง RGB เป็น float32 และ normalize (0-255 -> 0-1)
        buffer[pixelIndex++] = pixel.r / 255.0;
        buffer[pixelIndex++] = pixel.g / 255.0;
        buffer[pixelIndex++] = pixel.b / 255.0;
      }
    }

    return convertedBytes.buffer.asUint8List();
  }
}


