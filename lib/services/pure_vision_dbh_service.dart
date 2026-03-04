import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Rect;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
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
    final headers = <String, String>{
      'ngrok-skip-browser-warning': 'true',
    };
    final apiKey = AppConfig().mlApiKey;
    if (apiKey != null && apiKey.isNotEmpty) {
      headers['X-ML-API-Key'] = apiKey;
    }
    return headers;
  }

  /// 檢查 ML Service 是否可用
  /// 增加重試機制，避免 ngrok 或冷啟動導致誤判
  Future<bool> isServiceAvailable() async {
    final url = '$_baseUrl/health';
    debugPrint('[PureVisionDbhService] 檢查 ML Service: $url');

    // 嘗試兩次，第一次 10 秒，第二次 15 秒
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final timeout = attempt == 1 ? 10 : 15;
        final response = await http
            .get(Uri.parse(url), headers: _authHeaders)
            .timeout(Duration(seconds: timeout));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['status'] == 'ok') {
            debugPrint('[PureVisionDbhService] ML Service 可用 (attempt $attempt)');
            return true;
          }
        }
        debugPrint('[PureVisionDbhService] 非預期回應: ${response.statusCode}');
      } catch (e) {
        debugPrint('[PureVisionDbhService] attempt $attempt 失敗: $e');
        if (attempt < 2) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }
    debugPrint('[PureVisionDbhService] ML Service 不可用 (URL: $url)');
    return false;
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

  /// 取得 ML Service 設定（可用模式、模型資訊等）
  ///
  /// 呼叫 ML Service 的 /api/v1/config 端點
  /// 回傳 [MlServiceConfig] 包含可用的精度模式、模型名稱等
  Future<MlServiceConfig?> fetchMlConfig() async {
    try {
      final uri = Uri.parse('$_baseUrl/config');
      final response = await http
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return MlServiceConfig.fromJson(data);
      }
      debugPrint('[PureVisionDbhService] Config fetch failed: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('[PureVisionDbhService] Config fetch error: $e');
      return null;
    }
  }

  /// 全自動 DBH 測量 — 不需要手動框選樹幹
  ///
  /// 拍照 → AI 自動偵測樹幹 → 自動計算 DBH
  /// 類似 Tesla 純視覺：對準拍攝，AI 做所有事
  ///
  /// [mode] 精度模式：'fast'(~1.5s), 'balanced'(~3-6s), 'accurate'(~5-10s)
  ///        預設 null 時由 ML Service 決定（通常為 balanced）
  /// [tapX], [tapY] 使用者點擊的樹幹位置（SAM 分割 prompt，Phase 2+）
  /// [referenceDistanceM] 已知的參考距離（公尺），用於校正深度估計
  ///        例如手機 GPS 到樹的距離，ML Service 可用此校正 Depth Anything 的相對深度
  /// [instrumentDistanceM] 儀器水平距離 HD（公尺），作為備用參考距離
  /// [distanceSource] 距離來源：'gps'|'instrument'|'none'，讓 ML Service 選擇最佳策略
  Future<AutoMeasureResult> autoMeasureDbh({
    required File imageFile,
    double? focalLengthMm,
    double? focalLength35mm,
    double? fovDegrees,
    String? phoneMake,
    String? phoneModel,
    String? mode,
    int? tapX,
    int? tapY,
    double? referenceDistanceM,
    double? instrumentDistanceM,
    String? distanceSource,
    Rect? localBbox, // [Edge AI] The local tracking bounding box from ML Kit
    double? maskPixelWidth, // [方案A] YOLOv8-seg mask computed trunk pixel width
    bool returnVisualization = true,
    bool returnDetectionVisualization = true,
  }) async {
    // ngrok 免費版連線不穩，加重試邏輯
    const maxRetries = 2;
    Exception? lastError;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _doAutoMeasureRequest(
          imageFile: imageFile,
          focalLengthMm: focalLengthMm,
          focalLength35mm: focalLength35mm,
          fovDegrees: fovDegrees,
          phoneMake: phoneMake,
          phoneModel: phoneModel,
          mode: mode,
          tapX: tapX,
          tapY: tapY,
          referenceDistanceM: referenceDistanceM,
          instrumentDistanceM: instrumentDistanceM,
          distanceSource: distanceSource,
          localBbox: localBbox,
          maskPixelWidth: maskPixelWidth,
          returnVisualization: returnVisualization,
          returnDetectionVisualization: returnDetectionVisualization,
          attempt: attempt,
        );
        return result;
      } on PureVisionException {
        rethrow; // 伺服器明確回傳的錯誤，不重試
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('[PureVisionDbhService] attempt $attempt 失敗: $e');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
    throw PureVisionException('連線不穩定，已重試 $maxRetries 次: $lastError');
  }

  /// 實際發送 auto-measure-dbh 請求
  Future<AutoMeasureResult> _doAutoMeasureRequest({
    required File imageFile,
    double? focalLengthMm,
    double? focalLength35mm,
    double? fovDegrees,
    String? phoneMake,
    String? phoneModel,
    String? mode,
    int? tapX,
    int? tapY,
    double? referenceDistanceM,
    double? instrumentDistanceM,
    String? distanceSource,
    Rect? localBbox,
    double? maskPixelWidth,
    bool returnVisualization = true,
    bool returnDetectionVisualization = true,
    int attempt = 1,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/auto-measure-dbh');
      final request = http.MultipartRequest('POST', uri);

      request.headers.addAll(_authHeaders);

      // 明確設定 content type，避免 ngrok 或伺服器誤判
      request.files.add(
        await http.MultipartFile.fromPath(
          'image',
          imageFile.path,
          contentType: _guessImageMediaType(imageFile.path),
        ),
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
      if (mode != null) {
        request.fields['mode'] = mode;
      }
      // [Edge AI] Pass local bbox coordinates so server skips auto-detection
      if (localBbox != null) {
        request.fields['bbox_x1'] = localBbox.left.round().toString();
        request.fields['bbox_y1'] = localBbox.top.round().toString();
        request.fields['bbox_x2'] = localBbox.right.round().toString();
        request.fields['bbox_y2'] = localBbox.bottom.round().toString();
      }
      // [方案A] Seg mask trunk pixel width — overrides depth-edge detection
      if (maskPixelWidth != null && maskPixelWidth > 10) {
        request.fields['mask_pixel_width'] = maskPixelWidth.toStringAsFixed(2);
      }
      // [Phase 2] 參考距離校正
      if (referenceDistanceM != null && referenceDistanceM > 0) {
        request.fields['reference_distance'] = referenceDistanceM.toString();
      }
      // 儀器水平距離（ML Service 用於交叉驗證與 fallback）
      if (instrumentDistanceM != null && instrumentDistanceM > 0) {
        request.fields['instrument_distance'] = instrumentDistanceM.toString();
      }
      if (distanceSource != null) {
        request.fields['distance_source'] = distanceSource;
      }
      // SAM 分割觸碰點 (Phase 2+)
      if (tapX != null) {
        request.fields['tap_x'] = tapX.toString();
      }
      if (tapY != null) {
        request.fields['tap_y'] = tapY.toString();
      }

      debugPrint('[PureVisionDbhService] Auto-measure request to $uri'
          '${mode != null ? " (mode: $mode)" : ""}'
          ' [attempt $attempt]');
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        // 伺服器明確回傳的錯誤，拋 PureVisionException 不重試
        debugPrint('[PureVisionDbhService] 伺服器回傳 ${response.statusCode}: '
            '${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');
        throw PureVisionException(
          'API 錯誤 (${response.statusCode}): ${response.body}',
        );
      }

      final data = json.decode(response.body);
      return AutoMeasureResult.fromJson(data);
    } on PureVisionException {
      rethrow; // 伺服器錯誤，由上層 retry 決定是否重試
    } catch (e) {
      // SocketException / TimeoutException / ClientException → 交由 retry 邏輯處理
      rethrow;
    }
  }

  /// Multi-photo DBH measurement for higher accuracy
  ///
  /// Sends 2-3 photos to the backend, which runs depth estimation on each
  /// and takes the median DBH for noise reduction.
  Future<AutoMeasureResult> autoMeasureDbhMulti({
    required List<File> imageFiles,
    double? focalLengthMm,
    double? focalLength35mm,
    double? fovDegrees,
    String? phoneMake,
    String? phoneModel,
    double? referenceDistanceM,
    double? instrumentDistanceM,
    String? mode,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/auto-measure-dbh-multi');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(_authHeaders);

      for (final file in imageFiles) {
        request.files.add(
          await http.MultipartFile.fromPath('images', file.path),
        );
      }

      request.fields['fov_degrees'] = (fovDegrees ?? 70.0).toString();
      if (focalLengthMm != null) {
        request.fields['focal_length_mm'] = focalLengthMm.toString();
      }
      if (focalLength35mm != null) {
        request.fields['focal_length_35mm'] = focalLength35mm.toString();
      }
      if (phoneMake != null) request.fields['phone_make'] = phoneMake;
      if (phoneModel != null) request.fields['phone_model'] = phoneModel;
      if (referenceDistanceM != null && referenceDistanceM > 0) {
        request.fields['reference_distance'] = referenceDistanceM.toString();
      }
      if (instrumentDistanceM != null && instrumentDistanceM > 0) {
        request.fields['instrument_distance'] = instrumentDistanceM.toString();
      }
      if (mode != null) request.fields['mode'] = mode;

      debugPrint('[PureVisionDbhService] Multi-shot request (${imageFiles.length} images)');
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 300),
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
      throw PureVisionException('無法連接 ML 服務');
    } on TimeoutException {
      throw PureVisionException('多照片分析逾時');
    } on http.ClientException catch (e) {
      throw PureVisionException('網路錯誤: $e');
    }
  }

  /// 根據檔案副檔名猜測 MIME type
  MediaType _guessImageMediaType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'png':
        return MediaType('image', 'png');
      case 'webp':
        return MediaType('image', 'webp');
      case 'heic':
      case 'heif':
        return MediaType('image', 'heic');
      default:
        return MediaType('image', 'jpeg'); // 預設 JPEG
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

  static double _n(dynamic v, [double fallback = 0.0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  static int _i(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  factory PureVisionDbhResult.fromJson(Map<String, dynamic> json) {
    Uint8List? vizBytes;
    if (json['visualization_base64'] != null) {
      vizBytes = base64.decode(json['visualization_base64']);
    }

    final timing = json['timing'] ?? {};
    final imageSize = json['image_size'] ?? {};
    final notesList = json['notes'];

    return PureVisionDbhResult(
      dbhCm: _n(json['dbh_cm']),
      confidence: _n(json['confidence']),
      trunkDepthM: _n(json['trunk_depth_m']),
      trunkPixelWidth: _n(json['trunk_pixel_width']),
      chordLengthM: _n(json['chord_length_m']),
      focalLengthPx: _n(json['focal_length_px']),
      measurementRow: _i(json['measurement_row']),
      method: json['method']?.toString() ?? 'unknown',
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
        'x1': PureVisionDbhResult._i(b['x1']),
        'y1': PureVisionDbhResult._i(b['y1']),
        'x2': PureVisionDbhResult._i(b['x2']),
        'y2': PureVisionDbhResult._i(b['y2']),
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
      measurementRow: json['measurement_row'] != null ? PureVisionDbhResult._i(json['measurement_row']) : null,
      method: json['method']?.toString(),
      notes: notesList is List
          ? notesList.map((e) => e.toString()).toList()
          : <String>[],
      distanceStatus: json['distance_status']?.toString() ?? 'unknown',
      distanceMessage: json['distance_message']?.toString() ?? '',
      detectedBbox: bbox,
      detectionConfidence: (json['detection_confidence'] as num?)?.toDouble() ?? 0,
      allTrunks: trunksList.map((t) => DetectedTrunkInfo.fromJson(t)).toList(),
      depthEstimationMs: (timing['depth_estimation_ms'] as num?)?.toDouble() ?? 0,
      detectionMs: (timing['detection_ms'] as num?)?.toDouble() ?? 0,
      dbhCalculationMs: (timing['dbh_calculation_ms'] as num?)?.toDouble() ?? 0,
      totalMs: (timing['total_ms'] as num?)?.toDouble() ?? 0,
      visualizationBytes: vizBytes,
      detectionVisualizationBytes: detVizBytes,
      errorMessage: json['message']?.toString(),
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
      distanceStatus: json['distance_status']?.toString() ?? 'unknown',
      distanceMessage: json['distance_message']?.toString() ?? '',
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

/// ML Service 設定資訊
///
/// 從 /api/v1/config 端點取得，用於：
/// - 顯示目前使用的模型
/// - 列出可用的精度模式
/// - 顯示預估處理時間
class MlServiceConfig {
  final String activeDepthModelKey;
  final String activeDepthModelName;
  final double activeDepthModelParamsM;
  final String activeDepthModelLicense;
  final String activeSegmentationKey;
  final String activeSegmentationName;
  final bool onnxEnabled;
  final bool samEnabled;
  final Map<String, MlAccuracyMode> availableModes;

  MlServiceConfig({
    required this.activeDepthModelKey,
    required this.activeDepthModelName,
    required this.activeDepthModelParamsM,
    required this.activeDepthModelLicense,
    required this.activeSegmentationKey,
    required this.activeSegmentationName,
    required this.onnxEnabled,
    required this.samEnabled,
    required this.availableModes,
  });

  factory MlServiceConfig.fromJson(Map<String, dynamic> json) {
    final depth = json['active_depth_model'] as Map<String, dynamic>? ?? {};
    final seg = json['active_segmentation'] as Map<String, dynamic>? ?? {};
    final modesRaw = json['available_modes'] as Map<String, dynamic>? ?? {};

    final modes = <String, MlAccuracyMode>{};
    modesRaw.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        modes[key] = MlAccuracyMode.fromJson(key, value);
      }
    });

    return MlServiceConfig(
      activeDepthModelKey: depth['key'] as String? ?? 'unknown',
      activeDepthModelName: depth['name'] as String? ?? 'Unknown',
      activeDepthModelParamsM: (depth['params_m'] as num?)?.toDouble() ?? 0,
      activeDepthModelLicense: depth['license'] as String? ?? '',
      activeSegmentationKey: seg['key'] as String? ?? 'unknown',
      activeSegmentationName: seg['name'] as String? ?? 'Unknown',
      onnxEnabled: json['onnx_enabled'] == true,
      samEnabled: json['sam_enabled'] == true,
      availableModes: modes,
    );
  }
}

/// ML 精度模式資訊
class MlAccuracyMode {
  final String key;
  final String description;
  final String depthModel;
  final String segmentation;
  final double estimatedTimeS;
  final bool multiRow;
  final bool subpixel;
  final bool ellipseFit;

  MlAccuracyMode({
    required this.key,
    required this.description,
    required this.depthModel,
    required this.segmentation,
    required this.estimatedTimeS,
    required this.multiRow,
    required this.subpixel,
    required this.ellipseFit,
  });

  factory MlAccuracyMode.fromJson(String key, Map<String, dynamic> json) {
    final features = json['features'] as Map<String, dynamic>? ?? {};
    return MlAccuracyMode(
      key: key,
      description: json['description'] as String? ?? '',
      depthModel: json['depth_model'] as String? ?? '',
      segmentation: json['segmentation'] as String? ?? '',
      estimatedTimeS: (json['estimated_time_s'] as num?)?.toDouble() ?? 0,
      multiRow: features['multi_row'] == true,
      subpixel: features['subpixel'] == true,
      ellipseFit: features['ellipse_fit'] == true,
    );
  }

  /// 預估時間的中文描述
  String get estimatedTimeLabel {
    if (estimatedTimeS < 2) return '~${estimatedTimeS.toStringAsFixed(1)}秒 (快速)';
    if (estimatedTimeS < 8) return '~${estimatedTimeS.toStringAsFixed(0)}秒 (適中)';
    return '~${estimatedTimeS.toStringAsFixed(0)}秒 (較慢)';
  }
}
