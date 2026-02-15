import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// 純視覺 DBH 測量服務
///
/// 透過後端 ML Service (FastAPI + Depth Anything V2) 進行：
/// 1. 上傳照片 + 樹幹 bounding box
/// 2. 伺服器執行深度估計 + DBH 計算
/// 3. 回傳 DBH (cm)、信心度、視覺化結果
class PureVisionDbhService {
  static final PureVisionDbhService _instance = PureVisionDbhService._internal();
  factory PureVisionDbhService() => _instance;
  PureVisionDbhService._internal();

  String get _baseUrl => AppConfig().mlServiceUrl;

  /// 檢查 ML Service 是否可用
  Future<bool> isServiceAvailable() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status'] == 'ok';
      }
      return false;
    } catch (e) {
      debugPrint('[PureVisionDbhService] Service not available: $e');
      return false;
    }
  }

  /// 執行 DBH 測量
  ///
  /// [imageFile] 拍攝的照片
  /// [bboxX1], [bboxY1], [bboxX2], [bboxY2] 使用者框選的樹幹邊界框
  /// [fovDegrees] 相機水平視角 (預設 70°，若有 EXIF 焦距會自動計算)
  /// [focalLengthPx] 焦距像素值 (可選，自動估算)
  /// [focalLengthMm] EXIF 焦距 mm (可選，後端用來精確計算)
  /// [focalLength35mm] 35mm 等效焦距 (可選，後端用來精確計算 FOV)
  /// [returnVisualization] 是否回傳視覺化圖片
  Future<PureVisionDbhResult> measureDbh({
    required File imageFile,
    required int bboxX1,
    required int bboxY1,
    required int bboxX2,
    required int bboxY2,
    double? fovDegrees,
    double? focalLengthPx,
    double? focalLengthMm,
    double? focalLength35mm,
    bool returnVisualization = true,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/measure-dbh');
      final request = http.MultipartRequest('POST', uri);

      // 添加圖片
      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );

      // 添加 bounding box
      request.fields['bbox_x1'] = bboxX1.toString();
      request.fields['bbox_y1'] = bboxY1.toString();
      request.fields['bbox_x2'] = bboxX2.toString();
      request.fields['bbox_y2'] = bboxY2.toString();

      // 添加焦距相關參數為
      request.fields['fov_degrees'] = (fovDegrees ?? 70.0).toString();
      request.fields['use_multi_row'] = 'true';
      request.fields['return_visualization'] = returnVisualization.toString();

      if (focalLengthPx != null) {
        request.fields['focal_length_px'] = focalLengthPx.toString();
      }
      if (focalLengthMm != null) {
        request.fields['focal_length_mm'] = focalLengthMm.toString();
      }
      if (focalLength35mm != null) {
        request.fields['focal_length_35mm'] = focalLength35mm.toString();
      }

      debugPrint('[PureVisionDbhService] Sending request to $uri'
          '${focalLengthMm != null ? " (focal: ${focalLengthMm}mm)" : ""}'
          '${focalLength35mm != null ? " (35eq: ${focalLength35mm}mm)" : ""}');
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        throw PureVisionException(
          'API 錯誤 (${response.statusCode}): ${response.body}',
        );
      }

      final data = json.decode(response.body);
      if (data['success'] != true) {
        throw PureVisionException(data['detail'] ?? '未知錯誤');
      }

      return PureVisionDbhResult.fromJson(data);
    } on SocketException {
      throw PureVisionException('無法連接 ML 服務，請確認服務已啟動');
    } on http.ClientException catch (e) {
      throw PureVisionException('網路錯誤: $e');
    }
  }

  /// 取得照片中某一像素的深度值 (除錯用)
  Future<Map<String, dynamic>> depthAtPoint({
    required File imageFile,
    required int x,
    required int y,
  }) async {
    final uri = Uri.parse('$_baseUrl/debug/depth-at-point');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(
      await http.MultipartFile.fromPath('image', imageFile.path),
    );
    request.fields['x'] = x.toString();
    request.fields['y'] = y.toString();

    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 30),
    );
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw PureVisionException('API 錯誤 (${response.statusCode})');
    }

    return json.decode(response.body);
  }
}

/// 純視覺 DBH 測量結果
class PureVisionDbhResult {
  final double dbhCm;
  final double confidence;
  final double trunkDepthM;
  final double trunkPixelWidth;
  final double chordLengthM;
  final double focalLengthPx;
  final int measurementRow;
  final String method;
  final List<String> notes;
  final double depthEstimationMs;
  final double dbhCalculationMs;
  final double totalMs;
  final int imageWidth;
  final int imageHeight;
  final Uint8List? visualizationBytes;

  PureVisionDbhResult({
    required this.dbhCm,
    required this.confidence,
    required this.trunkDepthM,
    required this.trunkPixelWidth,
    required this.chordLengthM,
    required this.focalLengthPx,
    required this.measurementRow,
    required this.method,
    required this.notes,
    required this.depthEstimationMs,
    required this.dbhCalculationMs,
    required this.totalMs,
    required this.imageWidth,
    required this.imageHeight,
    this.visualizationBytes,
  });

  factory PureVisionDbhResult.fromJson(Map<String, dynamic> json) {
    Uint8List? vizBytes;
    if (json['visualization_base64'] != null) {
      vizBytes = base64.decode(json['visualization_base64']);
    }

    final timing = json['timing'] ?? {};
    final imageSize = json['image_size'] ?? {};
    final notesList = json['notes'];

    return PureVisionDbhResult(
      dbhCm: (json['dbh_cm'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
      trunkDepthM: (json['trunk_depth_m'] as num).toDouble(),
      trunkPixelWidth: (json['trunk_pixel_width'] as num).toDouble(),
      chordLengthM: (json['chord_length_m'] as num).toDouble(),
      focalLengthPx: (json['focal_length_px'] as num).toDouble(),
      measurementRow: json['measurement_row'] as int,
      method: json['method'] as String,
      notes: notesList is List
          ? notesList.map((e) => e.toString()).toList()
          : <String>[],
      depthEstimationMs: (timing['depth_estimation_ms'] as num?)?.toDouble() ?? 0,
      dbhCalculationMs: (timing['dbh_calculation_ms'] as num?)?.toDouble() ?? 0,
      totalMs: (timing['total_ms'] as num?)?.toDouble() ?? 0,
      imageWidth: (imageSize['width'] as num?)?.toInt() ?? 0,
      imageHeight: (imageSize['height'] as num?)?.toInt() ?? 0,
      visualizationBytes: vizBytes,
    );
  }

  /// 信心度等級 (中文)
  String get confidenceLevel {
    if (confidence >= 0.9) return '極高';
    if (confidence >= 0.75) return '高';
    if (confidence >= 0.6) return '中等';
    if (confidence >= 0.4) return '低';
    return '極低';
  }
}

/// 純視覺服務例外
class PureVisionException implements Exception {
  final String message;
  PureVisionException(this.message);

  @override
  String toString() => 'PureVisionException: $message';
}
