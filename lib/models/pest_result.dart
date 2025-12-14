class PestResult {
  final int totalPests;
  final double density; // ตัว/ตร.ม.
  final List<PestDetection> detections;

  PestResult({
    required this.totalPests,
    required this.density,
    required this.detections,
  });
}

class PestDetection {
  final double x;
  final double y;
  final double width;
  final double height;
  final double confidence;
  final String label;

  PestDetection({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
    required this.label,
  });
}


