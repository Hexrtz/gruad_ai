import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:io';

void main() => runApp(const MaterialApp(home: PestApp()));

class PestApp extends StatefulWidget {
  const PestApp({super.key});
  @override
  State<PestApp> createState() => _PestAppState();
}

class _PestAppState extends State<PestApp> {
  Interpreter? _interpreter;
  String _status = "กำลังโหลดโมเดล...";

  @override
  void initState() {
    super.initState();
    _initModel();
  }

  Future<void> _initModel() async {
    try {
      // โหลดโมเดล
      _interpreter = await Interpreter.fromAsset('assets/yolov8n.tflite');
      setState(() => _status = "✅ โมเดลพร้อมใช้งาน (YOLOv8)");
    } catch (e) {
      setState(() => _status = "❌ โหลดโมเดลไม่สำเร็จ: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pest Detection AI")), // แก้จาก app_bar เป็น appBar
      body: Center(child: Text(_status)),
    );
  }
}