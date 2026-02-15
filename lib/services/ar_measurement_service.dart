import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// AR DBH 測量服務
/// 
/// 提供多種測量方法：
/// 1. AR 深度測量 (ARKit LiDAR / ARCore Depth API)
/// 2. 雙點測量法 (用戶標記樹幹邊緣)
/// 3. 參照物比例法 (使用已知尺寸物體計算)
/// 4. 環繞拍攝法 (多角度照片計算)

/// 測量方法枚舉
enum MeasurementMethod {
  arDepth,        // AR 深度感測
  twoPoint,       // 雙點標記法
  reference,      // 參照物比例法
  multiAngle,     // 環繞拍攝法
  pureVision,     // 純視覺 AI 深度估計 (Depth Anything V2)
}

/// 測量點資料
class MeasurementPoint {
  final double x;
  final double y;
  final double? depth;  // 深度值 (公尺)
  final DateTime timestamp;
  
  MeasurementPoint({
    required this.x,
    required this.y,
    this.depth,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
  
  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'depth': depth,
    'timestamp': timestamp.toIso8601String(),
  };
  
  factory MeasurementPoint.fromJson(Map<String, dynamic> json) {
    return MeasurementPoint(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      depth: json['depth'] != null ? (json['depth'] as num).toDouble() : null,
      timestamp: json['timestamp'] != null 
          ? DateTime.parse(json['timestamp']) 
          : null,
    );
  }
}

/// 測量結果
class MeasurementResult {
  final double diameterCm;           // 直徑 (公分)
  final double confidenceScore;      // 信心度 (0-1)
  final MeasurementMethod method;    // 使用的方法
  final List<MeasurementPoint> points; // 測量點
  final String? notes;               // 備註
  final String? capturedImagePath;   // 拍攝影像路徑（可用於樹種辨識）
  final DateTime timestamp;
  
  MeasurementResult({
    required this.diameterCm,
    required this.confidenceScore,
    required this.method,
    required this.points,
    this.notes,
    this.capturedImagePath,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
  
  /// 計算圓周長 (公分)
  double get circumferenceCm => diameterCm * math.pi;
  
  /// 信心度等級
  String get confidenceLevel {
    if (confidenceScore >= 0.9) return '極高';
    if (confidenceScore >= 0.75) return '高';
    if (confidenceScore >= 0.6) return '中等';
    if (confidenceScore >= 0.4) return '低';
    return '極低';
  }
  
  /// 估計誤差範圍 (公分)
  double get estimatedErrorCm {
    // 根據方法和信心度估計誤差
    double baseError;
    switch (method) {
      case MeasurementMethod.arDepth:
        baseError = 1.0;  // ±1cm
        break;
      case MeasurementMethod.twoPoint:
        baseError = 2.0;  // ±2cm
        break;
      case MeasurementMethod.reference:
        baseError = 1.5;  // ±1.5cm
        break;
      case MeasurementMethod.multiAngle:
        baseError = 2.5;  // ±2.5cm
        break;
      case MeasurementMethod.pureVision:
        baseError = 3.0;  // ±3cm (neural network depth estimation)
        break;
    }
    return baseError * (2.0 - confidenceScore);
  }
  
  Map<String, dynamic> toJson() => {
    'diameter_cm': diameterCm,
    'confidence_score': confidenceScore,
    'method': method.name,
    'points': points.map((p) => p.toJson()).toList(),
    'notes': notes,
    'timestamp': timestamp.toIso8601String(),
    'circumference_cm': circumferenceCm,
    'estimated_error_cm': estimatedErrorCm,
    'captured_image_path': capturedImagePath,
  };
}

/// 設備能力檢測結果
class DeviceCapabilities {
  final bool hasARSupport;
  final bool hasLiDAR;
  final bool hasDepthAPI;
  final bool hasDualCamera;
  final String deviceModel;
  final String osVersion;
  
  DeviceCapabilities({
    required this.hasARSupport,
    required this.hasLiDAR,
    required this.hasDepthAPI,
    required this.hasDualCamera,
    required this.deviceModel,
    required this.osVersion,
  });
  
  /// 推薦的測量方法
  MeasurementMethod get recommendedMethod {
    if (hasLiDAR) return MeasurementMethod.arDepth;
    if (hasDepthAPI) return MeasurementMethod.arDepth;
    // 純視覺 AI 模式適用於所有設備
    return MeasurementMethod.pureVision;
  }
  
  /// 可用的測量方法列表
  List<MeasurementMethod> get availableMethods {
    List<MeasurementMethod> methods = [];
    
    if (hasLiDAR || hasDepthAPI) {
      methods.add(MeasurementMethod.arDepth);
    }
    
    // 這些方法都可用
    methods.add(MeasurementMethod.pureVision);
    methods.add(MeasurementMethod.twoPoint);
    methods.add(MeasurementMethod.reference);
    methods.add(MeasurementMethod.multiAngle);
    
    return methods;
  }
}

/// 參照物類型
class ReferenceObject {
  final String name;
  final String nameZh;
  final double widthCm;
  final double heightCm;
  final String iconName;
  
  const ReferenceObject({
    required this.name,
    required this.nameZh,
    required this.widthCm,
    required this.heightCm,
    required this.iconName,
  });
  
  /// 常用參照物
  static const List<ReferenceObject> commonObjects = [
    ReferenceObject(
      name: 'credit_card',
      nameZh: '信用卡',
      widthCm: 8.56,
      heightCm: 5.398,
      iconName: 'credit_card',
    ),
    ReferenceObject(
      name: 'a4_paper_short',
      nameZh: 'A4紙 (短邊水平)',
      // A4紙尺寸: 21.0 x 29.7 cm
      // 假設放在地上，短邊貼地垂直站立 (高度29.7)
      // 或者平放，長邊垂直於鏡頭方向 (高度29.7)
      // 這裡定義：寬度=21.0 (短邊), 高度=29.7 (長邊)
      widthCm: 21.0,
      heightCm: 29.7,
      iconName: 'description',
    ),
    ReferenceObject(
      name: 'smartphone_avg',
      nameZh: '智慧手機 (平均)',
      widthCm: 7.5,
      heightCm: 15.0,
      iconName: 'smartphone',
    ),
    ReferenceObject(
      name: 'ruler_30cm',
      nameZh: '30cm 直尺',
      widthCm: 30.0,
      heightCm: 3.0,
      iconName: 'straighten',
    ),
    ReferenceObject(
      name: 'measurement_card',
      nameZh: '專用測量卡 (15x10)',
      widthCm: 15.0,
      heightCm: 10.0,
      iconName: 'square_foot',
    ),
  ];
}

/// AR 測量服務
class ARMeasurementService {
  static final ARMeasurementService _instance = ARMeasurementService._internal();
  factory ARMeasurementService() => _instance;
  ARMeasurementService._internal();
  
  // 設備能力快取
  DeviceCapabilities? _cachedCapabilities;
  
  /// 檢測設備能力
  Future<DeviceCapabilities> detectDeviceCapabilities() async {
    if (_cachedCapabilities != null) return _cachedCapabilities!;
    
    bool hasARSupport = false;
    bool hasLiDAR = false;
    bool hasDepthAPI = false;
    bool hasDualCamera = false;
    String deviceModel = 'Unknown';
    String osVersion = 'Unknown';
    
    try {
      if (Platform.isIOS) {
        // iOS 設備檢測
        osVersion = 'iOS';
        
        // LiDAR 設備列表 (iPhone 12 Pro+, iPad Pro 2020+)
        // 實際應用中應使用 device_info_plus 獲取詳細型號
        hasARSupport = true;  // iOS 11+ 都支援 ARKit
        
        // 這裡假設較新的 iOS 設備有 LiDAR
        // 實際需要檢測設備型號
        hasLiDAR = false;  // 保守估計
        hasDepthAPI = true; // ARKit 支援深度
        hasDualCamera = true; // 大部分 iPhone 有雙鏡頭
        
      } else if (Platform.isAndroid) {
        // Android 設備檢測
        osVersion = 'Android';
        
        // ARCore 支援需要檢查
        hasARSupport = true;  // 假設支援 ARCore
        hasLiDAR = false;     // 大部分 Android 無 LiDAR
        hasDepthAPI = true;   // ARCore Depth API
        hasDualCamera = true; // 多數 Android 有多鏡頭
        
      } else {
        // 其他平台（桌面等）
        osVersion = Platform.operatingSystem;
      }
    } catch (e) {
      debugPrint('設備能力檢測失敗: $e');
    }
    
    _cachedCapabilities = DeviceCapabilities(
      hasARSupport: hasARSupport,
      hasLiDAR: hasLiDAR,
      hasDepthAPI: hasDepthAPI,
      hasDualCamera: hasDualCamera,
      deviceModel: deviceModel,
      osVersion: osVersion,
    );
    
    return _cachedCapabilities!;
  }
  
  /// 雙點測量法計算直徑
  /// 
  /// [point1] 和 [point2] 是螢幕上標記的兩個點
  /// [screenWidth] 和 [screenHeight] 是螢幕尺寸
  /// [focalLength] 是相機焦距 (像素)
  /// [distance] 是到樹幹的距離 (公尺)
  MeasurementResult calculateFromTwoPoints({
    required MeasurementPoint point1,
    required MeasurementPoint point2,
    required double screenWidth,
    required double screenHeight,
    required double distance,
    double? focalLength,
  }) {
    // 計算螢幕上兩點的像素距離
    double pixelDistance = math.sqrt(
      math.pow(point2.x - point1.x, 2) + 
      math.pow(point2.y - point1.y, 2)
    );
    
    // 使用預設焦距或提供的焦距
    // 典型手機相機焦距約為 26-28mm (35mm 等效)
    // 轉換為像素: focal_length_px ≈ width * focal_length_mm / sensor_width_mm
    double focalLengthPx = focalLength ?? (screenWidth * 4.0);
    
    // 計算實際直徑 (公尺)
    // 使用相似三角形: real_size / distance = pixel_size / focal_length
    double diameterM = (pixelDistance * distance) / focalLengthPx;
    double diameterCm = diameterM * 100;
    
    // 計算信心度
    // 考慮因素：距離、像素數量、點的位置
    double confidence = _calculateTwoPointConfidence(
      pixelDistance: pixelDistance,
      distance: distance,
      screenWidth: screenWidth,
    );
    
    return MeasurementResult(
      diameterCm: diameterCm,
      confidenceScore: confidence,
      method: MeasurementMethod.twoPoint,
      points: [point1, point2],
      notes: '距離: ${distance.toStringAsFixed(2)}m, 像素距離: ${pixelDistance.toStringAsFixed(0)}px',
    );
  }
  
  double _calculateTwoPointConfidence({
    required double pixelDistance,
    required double distance,
    required double screenWidth,
  }) {
    double confidence = 0.7;  // 基礎信心度
    
    // 距離因素: 0.5-3m 最佳
    if (distance >= 0.5 && distance <= 3.0) {
      confidence += 0.15;
    } else if (distance < 0.5 || distance > 5.0) {
      confidence -= 0.2;
    }
    
    // 像素數因素: 越多越好
    double pixelRatio = pixelDistance / screenWidth;
    if (pixelRatio >= 0.1 && pixelRatio <= 0.5) {
      confidence += 0.1;
    } else if (pixelRatio < 0.05) {
      confidence -= 0.15;
    }
    
    return confidence.clamp(0.0, 1.0);
  }
  
  /// 參照物比例法計算直徑
  MeasurementResult calculateFromReference({
    required ReferenceObject reference,
    required double referencePixelWidth,
    required double treePixelWidth,
  }) {
    // 計算比例 (cm/px)
    double scale = reference.widthCm / referencePixelWidth;
    double diameterCm = treePixelWidth * scale;
    
    // 計算信心度
    double confidence = _calculateReferenceConfidence(
      referencePixelWidth: referencePixelWidth,
      treePixelWidth: treePixelWidth,
    );
    
    return MeasurementResult(
      diameterCm: diameterCm,
      confidenceScore: confidence,
      method: MeasurementMethod.reference,
      points: [],
      notes: '參照物: ${reference.nameZh} (${reference.widthCm}cm)',
    );
  }

  /// [New] 計算虛擬 1.3m 高度的像素位置
  /// 
  /// 根據根部參照物的尺寸，推算螢幕上 1.3m 的位置
  /// [referencePixelHeight] 參照物在畫面中的像素高度
  /// [referenceActualHeightCm] 參照物實際高度 (cm)
  /// [referenceBottomY] 參照物底部在畫面中的 Y 座標 (通常是地面)
  /// 
  /// 返回：相對於 referenceBottomY 的像素偏移量 (向上為負)
  double calculateVirtualHeightOffset({
    required double referencePixelHeight,
    required double referenceActualHeightCm,
    double targetHeightCm = 130.0, // DBH 標準高度
  }) {
    // 計算比例尺 (px/cm)
    // 假設線性投影（在同一垂直平面上誤差可接受）
    double pixelsPerCm = referencePixelHeight / referenceActualHeightCm;
    
    // 計算目標高度的像素量
    double targetPixels = targetHeightCm * pixelsPerCm;
    
    return targetPixels;
  }
  
  double _calculateReferenceConfidence({
    required double referencePixelWidth,
    required double treePixelWidth,
  }) {
    double confidence = 0.75;  // 基礎信心度
    
    // 參照物清晰度因素
    if (referencePixelWidth >= 50) {
      confidence += 0.1;
    } else if (referencePixelWidth < 20) {
      confidence -= 0.15;
    }
    
    // 尺寸比例因素
    double ratio = treePixelWidth / referencePixelWidth;
    if (ratio >= 0.5 && ratio <= 5.0) {
      confidence += 0.1;
    }
    
    return confidence.clamp(0.0, 1.0);
  }
  
  /// 多角度環繞測量
  /// 
  /// 從多個角度的測量結果計算平均值和標準差
  MeasurementResult calculateFromMultiAngle({
    required List<MeasurementResult> measurements,
  }) {
    if (measurements.isEmpty) {
      throw ArgumentError('至少需要一個測量結果');
    }
    
    if (measurements.length == 1) {
      return measurements.first;
    }
    
    // 計算平均直徑
    double sumDiameter = 0;
    double sumConfidence = 0;
    List<MeasurementPoint> allPoints = [];
    
    for (var m in measurements) {
      sumDiameter += m.diameterCm;
      sumConfidence += m.confidenceScore;
      allPoints.addAll(m.points);
    }
    
    double avgDiameter = sumDiameter / measurements.length;
    double avgConfidence = sumConfidence / measurements.length;
    
    // 計算標準差
    double sumSquaredDiff = 0;
    for (var m in measurements) {
      sumSquaredDiff += math.pow(m.diameterCm - avgDiameter, 2);
    }
    double stdDev = math.sqrt(sumSquaredDiff / measurements.length);
    
    // 根據標準差調整信心度
    // 標準差越小，信心度越高
    double stdDevFactor = 1.0 - (stdDev / avgDiameter).clamp(0.0, 0.5);
    double finalConfidence = avgConfidence * stdDevFactor;
    
    // 多角度測量可以提升信心度
    double angleBonusconfidence = math.min(0.15, measurements.length * 0.03);
    finalConfidence = (finalConfidence + angleBonusconfidence).clamp(0.0, 1.0);
    
    return MeasurementResult(
      diameterCm: avgDiameter,
      confidenceScore: finalConfidence,
      method: MeasurementMethod.multiAngle,
      points: allPoints,
      notes: '${measurements.length} 次測量, 標準差: ${stdDev.toStringAsFixed(2)}cm',
    );
  }
  
  /// 從深度數據計算直徑 (AR Depth API)
  /// 
  /// [leftDepth] 和 [rightDepth] 是樹幹左右邊緣的深度值
  /// [centerDepth] 是樹幹中心的深度值
  /// [horizontalAngle] 是左右邊緣之間的水平角度 (弧度)
  MeasurementResult calculateFromDepth({
    required double leftDepth,
    required double rightDepth,
    required double centerDepth,
    required double horizontalAngle,
    required List<MeasurementPoint> points,
  }) {
    // 使用三角測量計算直徑
    // 樹幹直徑 ≈ 2 * centerDepth * tan(horizontalAngle / 2)
    double diameterM = 2 * centerDepth * math.tan(horizontalAngle / 2);
    double diameterCm = diameterM * 100;
    
    // 深度一致性檢查
    double depthVariance = (leftDepth - rightDepth).abs() / centerDepth;
    
    // 計算信心度
    double confidence = 0.85;  // AR 深度測量基礎信心度較高
    
    // 深度一致性影響
    if (depthVariance < 0.1) {
      confidence += 0.1;
    } else if (depthVariance > 0.3) {
      confidence -= 0.15;
    }
    
    // 距離因素
    if (centerDepth >= 0.5 && centerDepth <= 3.0) {
      confidence += 0.05;
    } else if (centerDepth > 5.0) {
      confidence -= 0.1;
    }
    
    return MeasurementResult(
      diameterCm: diameterCm,
      confidenceScore: confidence.clamp(0.0, 1.0),
      method: MeasurementMethod.arDepth,
      points: points,
      notes: '深度: ${centerDepth.toStringAsFixed(2)}m, 深度變異: ${(depthVariance * 100).toStringAsFixed(1)}%',
    );
  }
  
  /// 驗證測量結果的合理性
  bool validateMeasurement(MeasurementResult result) {
    // DBH 通常在 5-500cm 之間
    if (result.diameterCm < 5 || result.diameterCm > 500) {
      return false;
    }
    
    // 信心度太低
    if (result.confidenceScore < 0.3) {
      return false;
    }
    
    return true;
  }
  
  /// 獲取測量建議
  String getMeasurementTips(MeasurementMethod method) {
    switch (method) {
      case MeasurementMethod.arDepth:
        return '''
📱 AR 深度測量提示：
• 保持手機穩定，距離樹幹 0.5-3 公尺
• 確保光線充足
• 緩慢移動手機進行掃描
• 對準樹幹胸高位置 (1.3m)
''';
      case MeasurementMethod.twoPoint:
        return '''
👆 雙點測量提示：
• 點擊樹幹左右兩側邊緣
• 確保兩點在同一水平線上
• 輸入您與樹幹的距離
• 保持手機與樹幹平行
''';
      case MeasurementMethod.reference:
        return '''
📏 參照物測量提示 (iPhone 測距儀模式)：
1. 將 A4 紙或測量卡放在「樹根地面」
2. 在螢幕上框選地面的參照物
3. 系統會自動畫出 1.3m 高度線
4. 對準該線進行測量，無需手動量高
''';
      case MeasurementMethod.multiAngle:
        return '''
🔄 環繞測量提示：
• 從不同角度拍攝 3-5 張照片
• 每次旋轉約 45-90 度
• 保持與樹幹相同距離
• 系統會自動計算平均值
''';
      case MeasurementMethod.pureVision:
        return '''
🤖 純視覺 AI 測量提示：
• 距離樹幹 1-5 公尺處拍照
• 確保樹幹完整入鏡
• 用手指框選樹幹範圍
• AI 會自動估算深度並計算 DBH
• 不需要任何參照物或距離資料
''';
    }
  }
}
