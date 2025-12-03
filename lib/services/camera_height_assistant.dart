import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 相機高度輔助服務
/// 
/// 使用加速度計偵測手機傾斜度，結合使用者身高，
/// 引導用戶將相機對準 DBH 標準高度 (1.3m)
/// 
/// ============================================
/// 核心原理：固定持機姿勢 + 身高計算
/// ============================================
/// 
/// 要求使用者採用「標準持機姿勢」：
/// 1. 站直，手臂向前「水平伸直」（與身體成 90°）
/// 2. 手機螢幕面對自己（相機朝向樹幹）
/// 3. 此時相機高度 ≈ 肩膀高度 ≈ 身高 × 0.82
/// 
/// 人體測量學比例：
/// - 肩膀高度 ≈ 身高 × 0.82
/// - 手臂長度 ≈ 身高 × 0.44 (肩到指尖)
/// - 上臂+前臂 ≈ 身高 × 0.38 (肩到手腕)
/// 
/// 例如：身高 170cm 的人
/// - 肩膀高度 ≈ 170 × 0.82 = 139.4 cm
/// - 臂長 ≈ 170 × 0.38 = 64.6 cm
/// - 目標高度 = 130 cm  
/// - 需要向下傾斜 = arctan((139.4-130)/64.6) ≈ 8.3°
class CameraHeightAssistant {
  static final CameraHeightAssistant _instance = CameraHeightAssistant._internal();
  factory CameraHeightAssistant() => _instance;
  CameraHeightAssistant._internal();

  // 狀態
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  bool _isListening = false;
  
  // 傾斜數據
  double _pitch = 0.0;  // 俯仰角 (正值=向上傾斜, 負值=向下傾斜)
  double _roll = 0.0;   // 側傾角
  
  // 使用者設定
  double? _userHeightCm;  // 使用者身高 (cm)
  
  // 回調
  void Function(CameraAlignment)? _onAlignmentChanged;
  
  /// DBH 標準高度 (公分)
  static const double dbhStandardHeightCm = 130.0;
  
  /// 肩膀高度佔身高比例 (人體工學標準)
  /// 肩峰高度約為身高的 81-83%
  static const double shoulderHeightRatio = 0.82;
  
  /// 手臂長度佔身高比例 (肩到手腕)
  /// 上臂+前臂約為身高的 38-40%
  static const double armLengthRatio = 0.38;
  
  /// 取得目前傾斜角度
  double get pitch => _pitch;
  double get roll => _roll;
  
  /// 取得使用者身高
  double? get userHeightCm => _userHeightCm;
  
  /// 是否已設定身高
  bool get hasUserHeight => _userHeightCm != null && _userHeightCm! > 0;
  
  /// 計算肩膀高度 (cm) = 標準持機姿勢時的相機高度
  double? get shoulderHeightCm => _userHeightCm != null 
      ? _userHeightCm! * shoulderHeightRatio 
      : null;
  
  /// 計算手臂長度 (cm) = 肩到手腕
  double? get armLengthCm => _userHeightCm != null
      ? _userHeightCm! * armLengthRatio
      : null;
  
  /// 計算需要的俯仰角度才能對準 1.3m
  /// 負值 = 需要向下傾斜
  double? get targetPitchDegrees {
    final cameraHeight = shoulderHeightCm;
    final armLength = armLengthCm;
    if (cameraHeight == null || armLength == null) return null;
    
    // 高度差 (正值 = 相機比目標高)
    final heightDiffCm = cameraHeight - dbhStandardHeightCm;
    
    // tan(angle) = 高度差 / 臂長
    // angle = atan(高度差 / 臂長)
    final angleRad = math.atan(heightDiffCm / armLength);
    final angleDeg = angleRad * 180 / math.pi;
    
    // 返回需要傾斜的角度（正值=向下看，負值=向上看）
    return -angleDeg;
  }
  
  /// 載入已儲存的身高設定
  Future<void> loadUserHeight() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _userHeightCm = prefs.getDouble('user_height_cm');
      debugPrint('[CameraHeightAssistant] 載入身高: $_userHeightCm cm');
    } catch (e) {
      debugPrint('[CameraHeightAssistant] 載入身高失敗: $e');
    }
  }
  
  /// 設定使用者身高並儲存
  Future<void> setUserHeight(double heightCm) async {
    _userHeightCm = heightCm;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('user_height_cm', heightCm);
      debugPrint('[CameraHeightAssistant] 已儲存身高: $heightCm cm');
      debugPrint('[CameraHeightAssistant] 肩膀高度: ${shoulderHeightCm?.toStringAsFixed(1)} cm');
      debugPrint('[CameraHeightAssistant] 目標傾斜角: ${targetPitchDegrees?.toStringAsFixed(1)}°');
    } catch (e) {
      debugPrint('[CameraHeightAssistant] 儲存身高失敗: $e');
    }
  }
  
  /// 開始監聽感測器
  void startListening({void Function(CameraAlignment)? onAlignmentChanged}) {
    if (_isListening) return;
    
    _onAlignmentChanged = onAlignmentChanged;
    _isListening = true;
    
    try {
      _accelerometerSubscription = accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 100),
      ).listen((AccelerometerEvent event) {
        _processAccelerometerData(event);
      }, onError: (e) {
        debugPrint('[CameraHeightAssistant] 感測器錯誤: $e');
      });
    } catch (e) {
      debugPrint('[CameraHeightAssistant] 無法啟動感測器: $e');
      _isListening = false;
    }
  }
  
  /// 停止監聽
  void stopListening() {
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
    _isListening = false;
    _onAlignmentChanged = null;
  }
  
  /// 處理加速度計數據
  void _processAccelerometerData(AccelerometerEvent event) {
    // 計算傾斜角度 (使用重力方向)
    // X: 左右傾斜, Y: 前後傾斜, Z: 指向天/地
    final double x = event.x;
    final double y = event.y;
    final double z = event.z;
    
    // 計算俯仰角 (pitch): 手機前後傾斜
    // 當手機直立時 y ≈ g, z ≈ 0
    // 當手機水平（螢幕朝上）時 y ≈ 0, z ≈ g
    // 當手機橫向持握拍照時，我們需要不同的計算
    _pitch = math.atan2(y, z) * 180 / math.pi;
    
    // 計算側傾角 (roll): 手機左右傾斜
    _roll = math.atan2(x, z) * 180 / math.pi;
    
    // 判斷對準狀態
    final alignment = _calculateAlignment();
    _onAlignmentChanged?.call(alignment);
  }
  
  /// 計算相機對準狀態
  CameraAlignment _calculateAlignment() {
    final target = targetPitchDegrees;
    
    // 如果沒有設定身高，使用簡化模式（假設水平 = OK）
    if (target == null) {
      return _calculateSimpleAlignment();
    }
    
    // 計算與目標角度的差異
    final pitchError = _pitch - target;
    final absError = pitchError.abs();
    
    // 容許誤差：±3°（對應約 ±2.6cm 的高度誤差）
    const tolerance = 3.0;
    bool isOnTarget = absError < tolerance;
    bool isNearTarget = absError < 10.0;
    
    // 計算估計的相機高度
    final estimatedHeight = _calculateEstimatedCameraHeight();
    
    // 信心度
    double confidence = 1.0 - (absError / 45.0);
    confidence = confidence.clamp(0.0, 1.0);
    
    return CameraAlignment(
      pitch: _pitch,
      roll: _roll,
      targetPitch: target,
      pitchError: pitchError,
      isLevel: isOnTarget,
      isNearLevel: isNearTarget,
      direction: _getDirection(pitchError),
      confidence: confidence,
      guidance: _getSmartGuidance(pitchError, isOnTarget),
      estimatedCameraHeightCm: estimatedHeight,
      userHeightCm: _userHeightCm,
    );
  }
  
  /// 簡化模式（無身高設定）
  CameraAlignment _calculateSimpleAlignment() {
    final double absPitch = _pitch.abs();
    final double absRoll = _roll.abs();
    
    bool isLevel = absPitch < 5.0 && absRoll < 10.0;
    bool isNearLevel = absPitch < 15.0 && absRoll < 20.0;
    
    String direction;
    if (_pitch > 5) {
      direction = '向上';
    } else if (_pitch < -5) {
      direction = '向下';
    } else {
      direction = '水平';
    }
    
    double confidence = 1.0 - (absPitch / 90.0);
    confidence = confidence.clamp(0.0, 1.0);
    
    return CameraAlignment(
      pitch: _pitch,
      roll: _roll,
      targetPitch: 0,
      pitchError: _pitch,
      isLevel: isLevel,
      isNearLevel: isNearLevel,
      direction: direction,
      confidence: confidence,
      guidance: _getSimpleGuidance(),
      estimatedCameraHeightCm: null,
      userHeightCm: null,
    );
  }
  
  /// 計算估計的相機高度
  double? _calculateEstimatedCameraHeight() {
    if (shoulderHeightCm == null || armLengthCm == null) return null;
    
    // 根據實際俯仰角計算高度偏差
    final pitchRad = _pitch * math.pi / 180;
    final heightOffset = armLengthCm! * math.tan(pitchRad);
    
    // 相機高度 = 肩膀高度 - 高度偏差
    return shoulderHeightCm! - heightOffset;
  }
  
  String _getDirection(double error) {
    if (error > 5) return '太高';
    if (error < -5) return '太低';
    return '正確';
  }
  
  /// 智慧引導文字（有身高設定）
  String _getSmartGuidance(double error, bool isOnTarget) {
    if (isOnTarget) {
      return '✓ 已對準 1.3m，請拍攝！';
    }
    
    final absError = error.abs();
    
    if (_roll.abs() > 15) {
      return '↔ 請先將手機保持垂直';
    }
    
    if (error > 0) {
      // 相機指向太高，需要向下
      if (absError > 20) {
        return '↓ 請大幅向下傾斜手機';
      } else {
        return '↓ 請稍微向下傾斜';
      }
    } else {
      // 相機指向太低，需要向上
      if (absError > 20) {
        return '↑ 請大幅向上傾斜手機';
      } else {
        return '↑ 請稍微向上傾斜';
      }
    }
  }
  
  /// 簡化引導文字（無身高設定）
  String _getSimpleGuidance() {
    if (_pitch.abs() < 5 && _roll.abs() < 10) {
      return '✓ 相機已水平';
    } else if (_pitch > 10) {
      return '↓ 請將手機向下傾斜';
    } else if (_pitch < -10) {
      return '↑ 請將手機向上傾斜';
    } else if (_roll.abs() > 15) {
      return '↔ 請將手機保持垂直';
    } else {
      return '↔ 調整中...';
    }
  }
  
  /// 取得標準持機姿勢說明
  static String get postureInstructions => '''
📱 標準持機姿勢：

1️⃣ 站直，手臂向前「水平伸直」
   （與身體呈 90°，像在自拍）

2️⃣ 手機螢幕面對自己
   （相機朝向樹幹）

3️⃣ 跟隨水平儀引導，微調角度

這樣相機高度 ≈ 您的肩膀高度
系統會計算需要傾斜多少才能對準 1.3m
''';
  
  /// 釋放資源
  void dispose() {
    stopListening();
  }
}

/// 相機對準狀態
class CameraAlignment {
  final double pitch;             // 目前俯仰角 (度)
  final double roll;              // 目前側傾角 (度)
  final double targetPitch;       // 目標俯仰角 (度)
  final double pitchError;        // 俯仰角誤差 (度)
  final bool isLevel;             // 是否對準目標
  final bool isNearLevel;         // 是否接近目標
  final String direction;         // 指向方向描述
  final double confidence;        // 信心度 (0-1)
  final String guidance;          // 引導文字
  final double? estimatedCameraHeightCm;  // 估計相機高度 (cm)
  final double? userHeightCm;     // 使用者身高 (cm)
  
  const CameraAlignment({
    required this.pitch,
    required this.roll,
    required this.targetPitch,
    required this.pitchError,
    required this.isLevel,
    required this.isNearLevel,
    required this.direction,
    required this.confidence,
    required this.guidance,
    this.estimatedCameraHeightCm,
    this.userHeightCm,
  });
  
  /// 是否已設定身高（智慧模式）
  bool get hasUserHeight => userHeightCm != null;
  
  @override
  String toString() => 'CameraAlignment(pitch: ${pitch.toStringAsFixed(1)}°, '
      'target: ${targetPitch.toStringAsFixed(1)}°, '
      'height: ${estimatedCameraHeightCm?.toStringAsFixed(0)}cm)';
}

// Extension for accessing static from instance context  
extension CameraHeightAssistantExt on CameraHeightAssistant {
  String get postureGuide => CameraHeightAssistant.postureInstructions;
}
