import 'package:flutter/foundation.dart';

/// VLGEO2 BLE 封包解碼器
///
/// 基於深度協議分析的發現，正確處理 Nordic UART Service 封包邊界問題
///
/// ## 封包類型
/// | 類型 | 長度 | 特徵 | 處理方式 |
/// |------|------|------|----------|
/// | 正常封包 | 20 bytes | 不以 44 xx 00 開頭 | 保留全部 20 bytes |
/// | 殘留封包 | 5 bytes | 任何內容 | 只保留前 3 bytes |
/// | 標記封包 | 20 bytes | 以 44 xx 00 開頭 | 跳過前 3 bytes |
///
/// ## 協議背景
/// VLGEO2 使用 Nordic UART Service (NUS)，ATT MTU 為 20 bytes
/// - Service UUID: 9e000000-f685-4ea5-b58a-85287cb04965
/// - TX Characteristic UUID: 9e010000-f685-4ea5-b58a-85287cb04965
///
/// ## 問題根因
/// PacketLogger 會插入 3-byte 標記 (44 xx 00)，導致：
/// 1. 原本 20-byte 的數據被分成 5-byte 殘留 + 15-byte 部分
/// 2. 殘留封包的最後 2 bytes 是下一個封包的雜訊
/// 3. 標記封包的前 3 bytes 不是數據
class BlePacketDecoder {
  /// 解碼統計
  static int _normal20Count = 0;
  static int _residual5Count = 0;
  static int _marker44xxCount = 0;
  static int _otherCount = 0;
  static int _bytesDropped = 0;

  /// 重置統計
  static void resetStats() {
    _normal20Count = 0;
    _residual5Count = 0;
    _marker44xxCount = 0;
    _otherCount = 0;
    _bytesDropped = 0;
  }

  /// 獲取解碼統計
  static Map<String, int> getStats() => {
        'normal_20': _normal20Count,
        'residual_5': _residual5Count,
        'marker_44xx00': _marker44xxCount,
        'other': _otherCount,
        'bytes_dropped': _bytesDropped,
      };

  /// 解碼單個 BLE 封包
  ///
  /// 根據封包長度和特徵返回有效的數據 bytes
  ///
  /// [packetData] 原始封包數據 (List<int>)
  ///
  /// Returns: 有效的數據 bytes
  static List<int> decodePacket(List<int> packetData) {
    try {
      final int pktLen = packetData.length;

      if (pktLen == 20) {
        // 20-byte 封包：檢查是否以 44 xx 00 開頭
        if (pktLen >= 3 &&
            packetData[0] == 0x44 &&
            packetData[1] <= 0x0F &&
            packetData[2] == 0x00) {
          // 標記封包：跳過前 3 bytes
          _marker44xxCount++;
          _bytesDropped += 3;
          debugPrint(
              '[BLE DECODER] 標記封包 44 ${packetData[1].toRadixString(16).padLeft(2, '0').toUpperCase()} 00 - 跳過前 3 bytes');
          return packetData.sublist(3);
        } else {
          // 正常封包：保留全部
          _normal20Count++;
          return packetData;
        }
      } else if (pktLen == 5) {
        // 5-byte 殘留封包：只保留前 3 bytes
        _residual5Count++;
        _bytesDropped += 2;
        debugPrint(
            '[BLE DECODER] 殘留封包 (5 bytes) - 只保留前 3 bytes');
        return packetData.sublist(0, 3);
      } else {
        // 其他長度封包：過濾並保留 ASCII
        _otherCount++;
        List<int> filtered = [];
        for (int b in packetData) {
          if ((b >= 0x20 && b <= 0x7E) || b == 0x0D || b == 0x0A) {
            filtered.add(b);
          }
        }
        return filtered;
      }
    } catch (e) {
      debugPrint('[BlePacketDecoder] Error decoding packet: $e');
      return packetData;
    }
  }

  /// 列印解碼統計
  static void printStats() {
    final stats = getStats();
    debugPrint('=== BLE 封包解碼統計 ===');
    debugPrint('  正常 20-byte 封包: ${stats['normal_20']}');
    debugPrint('  5-byte 殘留封包: ${stats['residual_5']}');
    debugPrint('  44 xx 00 標記封包: ${stats['marker_44xx00']}');
    debugPrint('  其他封包: ${stats['other']}');
    debugPrint('  丟棄的 bytes: ${stats['bytes_dropped']}');
  }
}
