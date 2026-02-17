import 'dart:async';
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

  /// 取得 ML API Key 認證 headers
  Map<String, String> get _authHeaders {
    final apiKey = AppConfig().mlApiKey;
    if (apiKey != null && apiKey.isNotEmpty) {
      return {'X-ML-API-Key': apiKey};
    }
    return {};
  }

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
    String? phoneMake,
    String? phoneModel,
    bool returnVisualization = true,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/measure-dbh');
      final request = http.MultipartRequest('POST', uri);

      // 添加 ML API Key 認證
      request.headers.addAll(_authHeaders);

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
      if (phoneMake != null) {
        request.fields['phone_make'] = phoneMake;
      }
      if (phoneModel != null) {
        request.fields['phone_model'] = phoneModel;
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
    } on TimeoutException {
      throw PureVisionException('請求逾時，伺服器可能正在喚醒，請稍後再試');
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
    // 添加 ML API Key 認證
    request.headers.addAll(_authHeaders);
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

  /// 全自動 DBH 測量 — 不需要手動框選樹幹
  ///
  /// 拍照 → AI 自動偵測樹幹 → 自動計算 DBH
  /// 類似 Tesla 純視覺：對準拍攝，AI 做所有事
  Future<AutoMeasureResult> autoMeasureDbh({
    required File imageFile,
    double? focalLengthMm,
    double? focalLength35mm,
    double? fovDegrees,
    String? phoneMake,
    String? phoneModel,
    bool returnVisualization = true,
    bool returnDetectionVisualization = true,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/auto-measure-dbh');
      final request = http.MultipartRequest('POST', uri);

      // 添加 ML API Key 認證
      request.headers.addAll(_authHeaders);

      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );

      request.fields['fov_degrees'] = (fovDegrees ?? 70.0).toString();
      request.fields['return_visualization'] = returnVisualization.toString();
      request.fields['return_detection_visualization'] =
          returnDetectionVisualization.toString();

      if (focalLengthMm != null) {
        request.fields['focal_length_mm'] = focalLengthMm.toString();
      }
      if (focalLength35mm != null) {
        request.fields['focal_length_35mm'] = focalLength35mm.toString();
      }
      if (phoneMake != null) {
        request.fields['phone_make'] = phoneMake;
      }
      if (phoneModel != null) {
        request.fields['phone_model'] = phoneModel;
      }

      debugPrint('[PureVisionDbhService] Auto-measure request to $uri');
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
      return AutoMeasureResult.fromJson(data);
    } on SocketException {
      throw PureVisionException('無法連接 ML 服務，請確認服務已啟動');
    } on TimeoutException {
      throw PureVisionException('請求逾時，伺服器可能正在喚醒，請稍後再試');
    } on http.ClientException catch (e) {
      throw PureVisionException('網路錯誤: $e');
    }
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
      focalLengthPx: (json['focal_length_px'] as num?)?.toDouble() ?? 0,
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

/// 自動偵測 + 量測的結果
class AutoMeasureResult {
  final bool success;
  final bool autoDetected;

  // DBH 量測結果 (success == true 時有值)
  final double? dbhCm;
  final double? confidence;
  final double? trunkDepthM;
  final double? trunkPixelWidth;
  final double? chordLengthM;
  final double? focalLengthPx;
  final int? measurementRow;
  final String? method;
  final List<String> notes;

  // 距離驗證
  final String distanceStatus;   // "ok", "too_close", "too_far", "warning"
  final String distanceMessage;

  // 偵測到的框
  final Map<String, int>? detectedBbox;
  final double detectionConfidence;

  // 所有偵測到的樹幹
  final List<DetectedTrunkInfo> allTrunks;

  // 計時
  final double depthEstimationMs;
  final double detectionMs;
  final double dbhCalculationMs;
  final double totalMs;

  // 視覺化
  final Uint8List? visualizationBytes;
  final Uint8List? detectionVisualizationBytes;

  // 錯誤訊息
  final String? errorMessage;

  AutoMeasureResult({
    required this.success,
    this.autoDetected = false,
    this.dbhCm,
    this.confidence,
    this.trunkDepthM,
    this.trunkPixelWidth,
    this.chordLengthM,
    this.focalLengthPx,
    this.measurementRow,
    this.method,
    this.notes = const [],
    this.distanceStatus = 'unknown',
    this.distanceMessage = '',
    this.detectedBbox,
    this.detectionConfidence = 0,
    this.allTrunks = const [],
    this.depthEstimationMs = 0,
    this.detectionMs = 0,
    this.dbhCalculationMs = 0,
    this.totalMs = 0,
    this.visualizationBytes,
    this.detectionVisualizationBytes,
    this.errorMessage,
  });

  factory AutoMeasureResult.fromJson(Map<String, dynamic> json) {
    final timing = json['timing'] ?? {};

    Uint8List? vizBytes;
    if (json['visualization_base64'] != null) {
      vizBytes = base64.decode(json['visualization_base64']);
    }
    Uint8List? detVizBytes;
    if (json['detection_visualization_base64'] != null) {
      detVizBytes = base64.decode(json['detection_visualization_base64']);
    }

    final notesList = json['notes'];
    final trunksList = json['all_trunks'] as List? ?? [];

    Map<String, int>? bbox;
    if (json['detected_bbox'] != null) {
      final b = json['detected_bbox'];
      bbox = {
        'x1': (b['x1'] as num).toInt(),
        'y1': (b['y1'] as num).toInt(),
        'x2': (b['x2'] as num).toInt(),
        'y2': (b['y2'] as num).toInt(),
      };
    }

    return AutoMeasureResult(
      success: json['success'] == true,
      autoDetected: json['auto_detected'] == true,
      dbhCm: (json['dbh_cm'] as num?)?.toDouble(),
      confidence: (json['confidence'] as num?)?.toDouble(),
      trunkDepthM: (json['trunk_depth_m'] as num?)?.toDouble(),
      trunkPixelWidth: (json['trunk_pixel_width'] as num?)?.toDouble(),
      chordLengthM: (json['chord_length_m'] as num?)?.toDouble(),
      focalLengthPx: (json['focal_length_px'] as num?)?.toDouble(),
      measurementRow: json['measurement_row'] as int?,
      method: json['method'] as String?,
      notes: notesList is List
          ? notesList.map((e) => e.toString()).toList()
          : <String>[],
      distanceStatus: json['distance_status'] as String? ?? 'unknown',
      distanceMessage: json['distance_message'] as String? ?? '',
      detectedBbox: bbox,
      detectionConfidence: (json['detection_confidence'] as num?)?.toDouble() ?? 0,
      allTrunks: trunksList.map((t) => DetectedTrunkInfo.fromJson(t)).toList(),
      depthEstimationMs: (timing['depth_estimation_ms'] as num?)?.toDouble() ?? 0,
      detectionMs: (timing['detection_ms'] as num?)?.toDouble() ?? 0,
      dbhCalculationMs: (timing['dbh_calculation_ms'] as num?)?.toDouble() ?? 0,
      totalMs: (timing['total_ms'] as num?)?.toDouble() ?? 0,
      visualizationBytes: vizBytes,
      detectionVisualizationBytes: detVizBytes,
      errorMessage: json['message'] as String?,
    );
  }

  /// 信心度等級 (中文)
  String get confidenceLevel {
    final c = confidence ?? 0;
    if (c >= 0.9) return '極高';
    if (c >= 0.75) return '高';
    if (c >= 0.6) return '中等';
    if (c >= 0.4) return '低';
    return '極低';
  }

  /// 距離狀態是否正常
  bool get isDistanceOk =>
      distanceStatus == 'ok';

  /// 距離狀態 icon 顏色
  bool get isDistanceWarning =>
      distanceStatus == 'warning' ||
      distanceStatus == 'too_close' ||
      distanceStatus == 'too_far';
}

/// 偵測到的個別樹幹資訊
class DetectedTrunkInfo {
  final Map<String, int> bbox;
  final double confidence;
  final double depthM;
  final String distanceStatus;
  final String distanceMessage;

  DetectedTrunkInfo({
    required this.bbox,
    required this.confidence,
    required this.depthM,
    required this.distanceStatus,
    required this.distanceMessage,
  });

  factory DetectedTrunkInfo.fromJson(Map<String, dynamic> json) {
    final b = json['bbox'] ?? {};
    return DetectedTrunkInfo(
      bbox: {
        'x1': (b['x1'] as num?)?.toInt() ?? 0,
        'y1': (b['y1'] as num?)?.toInt() ?? 0,
        'x2': (b['x2'] as num?)?.toInt() ?? 0,
        'y2': (b['y2'] as num?)?.toInt() ?? 0,
      },
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      depthM: (json['depth_m'] as num?)?.toDouble() ?? 0,
      distanceStatus: json['distance_status'] as String? ?? 'unknown',
      distanceMessage: json['distance_message'] as String? ?? '',
    );
  }
}

/// 純視覺服務例外
class PureVisionException implements Exception {
  final String message;
  PureVisionException(this.message);

  @override
  String toString() => 'PureVisionException: $message';
}
