// ============================================================================
// V3 AR 測量整合服務 (AR Measurement Integration Service)
// ============================================================================
// 採用「兼容式開發」原則：
// - 獨立的 V3 服務，包裝現有 AR 功能
// - 提供更便捷的整合介面
// - 支援 ML 數據收集和校準
// ============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../ar_measurement_service.dart';

/// AR 測量模式
enum ARMeasurementMode {
  /// 雙點測量法
  twoPoint,
  
  /// 參照物測量法
  reference,
  
  /// 環繞拍攝法
  multiAngle,
  
  /// 快速估算（基於 ML 模型）
  quickEstimate,
}

/// 測量校準資料
class CalibrationData {
  final double deviceToTreeDistance;
  final double cameraHeight;
  final double sensorSize;
  final double focalLength;
  final DateTime calibratedAt;
  
  CalibrationData({
    required this.deviceToTreeDistance,
    required this.cameraHeight,
    required this.sensorSize,
    required this.focalLength,
    DateTime? calibratedAt,
  }) : calibratedAt = calibratedAt ?? DateTime.now();
  
  Map<String, dynamic> toJson() => {
    'deviceToTreeDistance': deviceToTreeDistance,
    'cameraHeight': cameraHeight,
    'sensorSize': sensorSize,
    'focalLength': focalLength,
    'calibratedAt': calibratedAt.toIso8601String(),
  };
  
  factory CalibrationData.fromJson(Map<String, dynamic> json) => CalibrationData(
    deviceToTreeDistance: (json['deviceToTreeDistance'] as num).toDouble(),
    cameraHeight: (json['cameraHeight'] as num).toDouble(),
    sensorSize: (json['sensorSize'] as num).toDouble(),
    focalLength: (json['focalLength'] as num).toDouble(),
    calibratedAt: DateTime.parse(json['calibratedAt']),
  );
  
  /// 標準校準資料（預設值）
  static CalibrationData get standard => CalibrationData(
    deviceToTreeDistance: 1.5,
    cameraHeight: 1.3, // DBH 標準高度
    sensorSize: 6.17, // 常見手機 sensor size (mm)
    focalLength: 4.71, // 常見手機焦距 (mm)
  );
}

/// 增強測量結果
class EnhancedMeasurementResult {
  final double dbhValue;
  final double confidence;
  final ARMeasurementMode mode;
  final CalibrationData calibration;
  final List<double>? multiAngleValues;
  final File? measurementImage;
  final Map<String, dynamic> metadata;
  final DateTime measuredAt;
  
  EnhancedMeasurementResult({
    required this.dbhValue,
    required this.confidence,
    required this.mode,
    required this.calibration,
    this.multiAngleValues,
    this.measurementImage,
    Map<String, dynamic>? metadata,
    DateTime? measuredAt,
  }) : 
    metadata = metadata ?? {},
    measuredAt = measuredAt ?? DateTime.now();
  
  /// 信賴區間（基於信心度）
  double get marginOfError => dbhValue * (1 - confidence) * 0.5;
  
  /// 最小可能值
  double get minValue => (dbhValue - marginOfError).clamp(0, double.infinity);
  
  /// 最大可能值
  double get maxValue => dbhValue + marginOfError;
  
  /// 品質等級
  String get qualityGrade {
    if (confidence >= 0.9) return 'A';
    if (confidence >= 0.8) return 'B';
    if (confidence >= 0.7) return 'C';
    if (confidence >= 0.5) return 'D';
    return 'F';
  }
  
  Map<String, dynamic> toJson() => {
    'dbhValue': dbhValue,
    'confidence': confidence,
    'mode': mode.index,
    'calibration': calibration.toJson(),
    'multiAngleValues': multiAngleValues,
    'metadata': metadata,
    'measuredAt': measuredAt.toIso8601String(),
  };
}

/// V3 AR 測量整合服務 - 單例模式
class ARMeasurementIntegrationService {
  static final ARMeasurementIntegrationService _instance = 
      ARMeasurementIntegrationService._internal();
  factory ARMeasurementIntegrationService() => _instance;
  ARMeasurementIntegrationService._internal();
  
  // 底層服務
  final ARMeasurementService _arService = ARMeasurementService();
  
  // 狀態
  CalibrationData _currentCalibration = CalibrationData.standard;
  DeviceCapabilities? _deviceCapabilities;
  bool _initialized = false;
  
  // 測量歷史（本次會話）
  final List<EnhancedMeasurementResult> _sessionHistory = [];
  
  /// 取得目前校準資料
  CalibrationData get calibration => _currentCalibration;
  
  /// 取得會話歷史
  List<EnhancedMeasurementResult> get sessionHistory => 
      List.unmodifiable(_sessionHistory);
  
  /// 初始化服務
  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      _deviceCapabilities = await _arService.detectDeviceCapabilities();
      
      // 根據設備能力調整預設校準（使用標準值，因為 DeviceCapabilities 不包含 sensor 資訊）
      _currentCalibration = CalibrationData.standard;
      
      _initialized = true;
      debugPrint('[ARMeasurementIntegration] 初始化完成');
      
    } catch (e) {
      debugPrint('[ARMeasurementIntegration] 初始化失敗: $e');
      // 使用標準校準資料
      _currentCalibration = CalibrationData.standard;
      _initialized = true;
    }
  }
  
  /// 更新校準資料
  void updateCalibration(CalibrationData calibration) {
    _currentCalibration = calibration;
  }
  
  /// 快速 DBH 測量（單張照片）
  /// 
  /// 使用雙點測量法的簡化版本
  Future<EnhancedMeasurementResult?> quickMeasure({
    required File image,
    required Offset leftEdge,
    required Offset rightEdge,
    required Size imageSize,
    double? estimatedDistance,
  }) async {
    try {
      // 計算像素寬度
      final pixelWidth = (rightEdge.dx - leftEdge.dx).abs();
      
      // 使用當前校準計算 DBH
      final distance = estimatedDistance ?? _currentCalibration.deviceToTreeDistance;
      final dbh = _calculateDBH(
        pixelWidth: pixelWidth,
        imageWidth: imageSize.width,
        distance: distance,
      );
      
      // 估算信心度
      final confidence = _estimateConfidence(
        pixelWidth: pixelWidth,
        imageWidth: imageSize.width,
        hasCalibration: estimatedDistance != null,
      );
      
      final result = EnhancedMeasurementResult(
        dbhValue: dbh,
        confidence: confidence,
        mode: ARMeasurementMode.quickEstimate,
        calibration: _currentCalibration,
        measurementImage: image,
        metadata: {
          'pixelWidth': pixelWidth,
          'imageWidth': imageSize.width,
          'distance': distance,
          'leftEdge': {'x': leftEdge.dx, 'y': leftEdge.dy},
          'rightEdge': {'x': rightEdge.dx, 'y': rightEdge.dy},
        },
      );
      
      _sessionHistory.add(result);
      
      // 記錄測量資訊（未來可用於 ML）
      debugPrint('[ARMeasurementIntegration] 快速測量完成: ${result.dbhValue.toStringAsFixed(1)} cm');
      
      return result;
      
    } catch (e) {
      debugPrint('[ARMeasurementIntegration] 快速測量失敗: $e');
      return null;
    }
  }
  
  /// 參照物測量
  Future<EnhancedMeasurementResult?> measureWithReference({
    required File image,
    required double referenceActualWidth, // 參照物實際寬度 (cm)
    required double referencePixelWidth,  // 參照物像素寬度
    required double treePixelWidth,       // 樹幹像素寬度
    String? referenceName,
  }) async {
    try {
      // 計算比例
      final pixelToCm = referenceActualWidth / referencePixelWidth;
      final dbh = treePixelWidth * pixelToCm;
      
      // 參照物測量通常較準確
      final confidence = _estimateReferenceConfidence(
        referencePixelWidth: referencePixelWidth,
        treePixelWidth: treePixelWidth,
      );
      
      final result = EnhancedMeasurementResult(
        dbhValue: dbh,
        confidence: confidence,
        mode: ARMeasurementMode.reference,
        calibration: _currentCalibration,
        measurementImage: image,
        metadata: {
          'referenceName': referenceName,
          'referenceActualWidth': referenceActualWidth,
          'referencePixelWidth': referencePixelWidth,
          'treePixelWidth': treePixelWidth,
          'pixelToCm': pixelToCm,
        },
      );
      
      _sessionHistory.add(result);
      
      return result;
      
    } catch (e) {
      debugPrint('[ARMeasurementIntegration] 參照物測量失敗: $e');
      return null;
    }
  }
  
  /// 多角度測量（環繞拍攝）
  Future<EnhancedMeasurementResult?> measureMultiAngle({
    required List<MeasurementResult> angleResults,
  }) async {
    if (angleResults.isEmpty) return null;
    
    try {
      // 提取所有 DBH 值（使用 diameterCm 屬性）
      final values = angleResults
          .map((r) => r.diameterCm)
          .where((d) => d > 0)
          .toList();
      
      if (values.isEmpty) return null;
      
      // 計算加權平均（移除異常值）
      final filteredValues = _removeOutliers(values);
      final avgDbh = filteredValues.reduce((a, b) => a + b) / filteredValues.length;
      
      // 計算標準差
      final variance = filteredValues
          .map((v) => (v - avgDbh) * (v - avgDbh))
          .reduce((a, b) => a + b) / filteredValues.length;
      final stdDev = math.sqrt(variance);
      
      // 多角度測量的信心度基於標準差
      final confidence = _estimateMultiAngleConfidence(
        values: filteredValues,
        stdDev: stdDev,
      );
      
      final result = EnhancedMeasurementResult(
        dbhValue: avgDbh,
        confidence: confidence,
        mode: ARMeasurementMode.multiAngle,
        calibration: _currentCalibration,
        multiAngleValues: filteredValues,
        metadata: {
          'angleCount': angleResults.length,
          'usedCount': filteredValues.length,
          'stdDev': stdDev,
          'rawValues': values,
        },
      );
      
      _sessionHistory.add(result);
      
      return result;
      
    } catch (e) {
      debugPrint('[ARMeasurementIntegration] 多角度測量失敗: $e');
      return null;
    }
  }
  
  /// 計算 DBH（雙點法）
  double _calculateDBH({
    required double pixelWidth,
    required double imageWidth,
    required double distance,
  }) {
    // 視角計算
    final fov = 2 * math.atan(_currentCalibration.sensorSize / 
        (2 * _currentCalibration.focalLength));
    
    // 實際視野寬度（在距離 distance 處）
    final viewWidth = 2 * distance * math.tan(fov / 2) * 100; // 轉換為 cm
    
    // 計算 DBH
    final dbh = (pixelWidth / imageWidth) * viewWidth;
    
    return dbh;
  }
  
  /// 估算信心度（快速測量）
  double _estimateConfidence({
    required double pixelWidth,
    required double imageWidth,
    required bool hasCalibration,
  }) {
    double confidence = 0.5; // 基礎信心度
    
    // 像素佔比越大，越準確
    final ratio = pixelWidth / imageWidth;
    if (ratio >= 0.3) {
      confidence += 0.2;
    } else if (ratio >= 0.15) {
      confidence += 0.1;
    }
    
    // 有校準資料加分
    if (hasCalibration) {
      confidence += 0.15;
    }
    
    // 設備能力加分
    if (_deviceCapabilities != null) {
      if (_deviceCapabilities!.hasDepthAPI) {
        confidence += 0.1;
      }
      if (_deviceCapabilities!.hasLiDAR) {
        confidence += 0.15;
      }
    }
    
    return confidence.clamp(0.0, 0.95);
  }
  
  /// 估算信心度（參照物測量）
  double _estimateReferenceConfidence({
    required double referencePixelWidth,
    required double treePixelWidth,
  }) {
    double confidence = 0.75; // 參照物法基礎信心度較高
    
    // 參照物像素寬度越大越準確
    if (referencePixelWidth >= 100) {
      confidence += 0.1;
    }
    
    // 樹幹像素寬度越大越準確
    if (treePixelWidth >= 50) {
      confidence += 0.05;
    }
    
    return confidence.clamp(0.0, 0.95);
  }
  
  /// 估算信心度（多角度測量）
  double _estimateMultiAngleConfidence({
    required List<double> values,
    required double stdDev,
  }) {
    double confidence = 0.7; // 多角度法基礎信心度
    
    // 測量次數越多越準確
    if (values.length >= 5) {
      confidence += 0.15;
    } else if (values.length >= 3) {
      confidence += 0.1;
    }
    
    // 標準差越小越準確
    final avgDbh = values.reduce((a, b) => a + b) / values.length;
    final coeffOfVariation = stdDev / avgDbh;
    
    if (coeffOfVariation < 0.05) {
      confidence += 0.1;
    } else if (coeffOfVariation < 0.1) {
      confidence += 0.05;
    }
    
    return confidence.clamp(0.0, 0.95);
  }
  
  /// 移除異常值（IQR 方法）
  List<double> _removeOutliers(List<double> values) {
    if (values.length < 4) return values;
    
    final sorted = List<double>.from(values)..sort();
    final q1 = sorted[(sorted.length * 0.25).floor()];
    final q3 = sorted[(sorted.length * 0.75).floor()];
    final iqr = q3 - q1;
    
    final lowerBound = q1 - 1.5 * iqr;
    final upperBound = q3 + 1.5 * iqr;
    
    return values.where((v) => v >= lowerBound && v <= upperBound).toList();
  }
  
  /// 清除會話歷史
  void clearSessionHistory() {
    _sessionHistory.clear();
  }
  
  /// 取得推薦的測量方法
  ARMeasurementMode getRecommendedMode() {
    if (_deviceCapabilities == null) {
      return ARMeasurementMode.reference; // 最可靠
    }
    
    if (_deviceCapabilities!.hasLiDAR) {
      return ARMeasurementMode.twoPoint; // LiDAR 設備雙點法最佳
    }
    
    if (_deviceCapabilities!.hasDepthAPI) {
      return ARMeasurementMode.twoPoint;
    }
    
    return ARMeasurementMode.reference; // 一般設備用參照物法
  }
  
  /// 取得測量方法的說明
  static String getModeDescription(ARMeasurementMode mode) {
    switch (mode) {
      case ARMeasurementMode.twoPoint:
        return '拍攝樹幹照片，點擊標記兩側邊緣計算直徑';
      case ARMeasurementMode.reference:
        return '將已知尺寸的物體（如 A4 紙、捲尺）放在樹幹旁作為參照';
      case ARMeasurementMode.multiAngle:
        return '從多個角度拍攝樹幹，系統計算平均值提高準確度';
      case ARMeasurementMode.quickEstimate:
        return '快速估算，適用於初步調查';
    }
  }
}

/// AR 測量快速入口 Widget
class ARMeasurementQuickWidget extends StatelessWidget {
  final double? currentDbh;
  final String? speciesName;
  final ValueChanged<EnhancedMeasurementResult>? onMeasured;
  
  const ARMeasurementQuickWidget({
    Key? key,
    this.currentDbh,
    this.speciesName,
    this.onMeasured,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () => _openARMeasurement(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.camera_enhance,
                  color: Colors.teal,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AR DBH 測量',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currentDbh != null 
                        ? '目前值: ${currentDbh!.toStringAsFixed(1)} cm'
                        : '使用相機智慧測量樹幹直徑',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.grey,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _openARMeasurement(BuildContext context) {
    // 這裡導航到 AR 測量頁面
    // 需要 import 對應的頁面
    Navigator.of(context).pushNamed(
      '/ar-dbh-measurement',
      arguments: {
        'initialDbh': currentDbh,
        'speciesName': speciesName,
      },
    ).then((result) {
      if (result is EnhancedMeasurementResult) {
        onMeasured?.call(result);
      }
    });
  }
}
