import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// DBH 量測引擎：最終以 [DbhEngine.xiangLidar] 為主，[DbhEngine.visionMono] 為過渡／fallback。
enum DbhEngine {
  /// Xiang et al.：LiDAR metric depth + 地面平面 + 1.3 m 帶（待後端 `/measure-dbh-xiang`）
  xiangLidar,

  /// 單目 DA3 + YOLO multi-row（現行 AutoPilot，長期保留作無 LiDAR／Xiang 失敗時備援）
  visionMono,

  /// VLGEO2 Remote Diameter（BLE NMEA CM 欄）
  instrumentRemote,

  /// 胸徑尺／卷尺手動輸入
  manual,
}

extension DbhEngineLabels on DbhEngine {
  String get logTag => name;

  String get displayName {
    switch (this) {
      case DbhEngine.xiangLidar:
        return 'LiDAR / Xiang';
      case DbhEngine.visionMono:
        return '視覺 DBH（單目）';
      case DbhEngine.instrumentRemote:
        return '儀器 Remote Dia';
      case DbhEngine.manual:
        return '手動輸入';
    }
  }

  /// 對應後端 `measurement_method` 建議值。
  String get defaultMeasurementMethod {
    switch (this) {
      case DbhEngine.xiangLidar:
        return 'xiang_lidar';
      case DbhEngine.visionMono:
        return 'autopilot_vision';
      case DbhEngine.instrumentRemote:
        return 'remote_diameter';
      case DbhEngine.manual:
        return 'manual_input';
    }
  }
}

/// 裝置是否「可能」具 LiDAR（硬體粗筛；實際仍須 depth frame + Xiang preflight）。
class DbhHardwareCapabilities {
  final bool reportsLidarHardware;
  final String platform;
  final String? deviceModel;
  final String? deviceBrand;

  const DbhHardwareCapabilities({
    required this.reportsLidarHardware,
    required this.platform,
    this.deviceModel,
    this.deviceBrand,
  });

  String get summary =>
      'platform=$platform model=${deviceModel ?? "?"} '
      'lidarHardware=$reportsLidarHardware';
}

class DbhEngineResolution {
  final DbhEngine engine;
  final DbhEngine apiEngine;
  final String reason;

  const DbhEngineResolution({
    required this.engine,
    required this.apiEngine,
    required this.reason,
  });

  /// 路由建議的引擎；[apiEngine] 是本次實際會呼叫的 API（Xiang 未就緒時可 fallback）。
  String get summary => 'engine=${engine.logTag} api=${apiEngine.logTag} ($reason)';
}

/// 探測裝置 LiDAR 能力（啟動時一次即可）。
class DbhCapabilityService {
  DbhCapabilityService._();
  static final DbhCapabilityService instance = DbhCapabilityService._();

  DbhHardwareCapabilities? _cached;

  /// 後端 Xiang endpoint 就緒後改為 true，並實作 LiDAR depth 采集。
  static bool xiangApiEnabled = false;

  Future<DbhHardwareCapabilities> ensureLoaded() async {
    if (_cached != null) return _cached!;
    _cached = await _probe();
    debugPrint('[DBH] capabilities: ${_cached!.summary} '
        'xiangApiEnabled=$xiangApiEnabled');
    return _cached!;
  }

  Future<DbhHardwareCapabilities> _probe() async {
    final plugin = DeviceInfoPlugin();
    try {
      if (Platform.isIOS) {
        final ios = await plugin.iosInfo;
        final machine = ios.utsname.machine;
        return DbhHardwareCapabilities(
          reportsLidarHardware: _iosMachineHasLidar(machine),
          platform: 'ios',
          deviceModel: machine,
          deviceBrand: 'Apple',
        );
      }
      if (Platform.isAndroid) {
        final android = await plugin.androidInfo;
        return DbhHardwareCapabilities(
          reportsLidarHardware: false,
          platform: 'android',
          deviceModel: android.model,
          deviceBrand: android.brand,
        );
      }
    } catch (e) {
      debugPrint('[DBH] capabilities probe failed: $e');
    }
    return const DbhHardwareCapabilities(
      reportsLidarHardware: false,
      platform: 'unknown',
    );
  }
}

/// Apple 具 LiDAR 的 identifier（Scene Depth；不含一般 Pro 以外的機型）。
/// 參考：https://github.com/devicekit/DeviceKit 等社群列表；僅作 routing 粗筛。
bool _iosMachineHasLidar(String machine) {
  const lidarMachines = {
    'iPhone12,3', 'iPhone12,5',
    'iPhone13,3', 'iPhone13,4',
    'iPhone14,2', 'iPhone14,3', 'iPhone14,4', 'iPhone14,5',
    'iPhone15,2', 'iPhone15,3', 'iPhone15,4', 'iPhone15,5',
    'iPhone16,1', 'iPhone16,2', 'iPhone17,1', 'iPhone17,2',
    'iPhone17,3', 'iPhone17,4',
    'iPad13,4', 'iPad13,5', 'iPad13,6', 'iPad13,7',
    'iPad14,3', 'iPad14,4', 'iPad14,5', 'iPad14,6',
    'iPad16,3', 'iPad16,4', 'iPad16,5', 'iPad16,6',
  };
  return lidarMachines.contains(machine);
}

class DbhEngineResolver {
  DbhEngineResolver._();

  /// 自動拍照量 DBH 時：決定理想引擎與本次實際呼叫的 API。
  static DbhEngineResolution resolveForAutoMeasure({
    required DbhHardwareCapabilities hardware,
    bool hasLidarDepthFrame = false,
    bool xiangPreflightOk = false,
  }) {
    final xiangReady = DbhCapabilityService.xiangApiEnabled;

    if (xiangReady &&
        hasLidarDepthFrame &&
        xiangPreflightOk &&
        hardware.reportsLidarHardware) {
      return const DbhEngineResolution(
        engine: DbhEngine.xiangLidar,
        apiEngine: DbhEngine.xiangLidar,
        reason: 'lidar depth frame + xiang preflight ok',
      );
    }

    if (hardware.reportsLidarHardware && !xiangReady) {
      return const DbhEngineResolution(
        engine: DbhEngine.xiangLidar,
        apiEngine: DbhEngine.visionMono,
        reason: 'lidar hardware present but xiang API not enabled yet → vision fallback',
      );
    }

    if (hardware.reportsLidarHardware && hasLidarDepthFrame && !xiangPreflightOk) {
      return const DbhEngineResolution(
        engine: DbhEngine.xiangLidar,
        apiEngine: DbhEngine.visionMono,
        reason: 'xiang preflight failed → vision fallback',
      );
    }

    if (hardware.reportsLidarHardware && !hasLidarDepthFrame) {
      return const DbhEngineResolution(
        engine: DbhEngine.xiangLidar,
        apiEngine: DbhEngine.visionMono,
        reason: 'no lidar depth frame captured → vision fallback',
      );
    }

    return const DbhEngineResolution(
      engine: DbhEngine.visionMono,
      apiEngine: DbhEngine.visionMono,
      reason: 'no lidar hardware → vision mono',
    );
  }

  /// 表單提交／來源 chip 對應的引擎。
  static DbhEngine fromFormSource(String? source) {
    switch (source) {
      case 'remote_diameter':
        return DbhEngine.instrumentRemote;
      case 'vision':
        return DbhEngine.visionMono;
      case 'manual':
        return DbhEngine.manual;
      default:
        return DbhEngine.manual;
    }
  }
}
