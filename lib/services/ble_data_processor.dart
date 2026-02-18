import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'ble_field_validator.dart';

class BleDataProcessor {
  // CSV 欄位索引 (基於 DATA_2.CSV)
  static const int _idxType = 2;
  static const int _idxId = 6;
  static const int _idxLat = 12;
  static const int _idxNS = 13;
  static const int _idxLon = 14;
  static const int _idxEW = 15;
  static const int _idxAlt = 16; // Altitude
  static const int _idxDate = 18;
  static const int _idxTime = 19;
  static const int _idxSD = 23; // Slope Distance
  static const int _idxHD = 24; // Horizontal Distance
  static const int _idxH = 25; // Height
  static const int _idxDia = 26; // Diameter
  static const int _idxPitch = 27; // Pitch/Inclination
  static const int _idxAz = 28; // Azimuth

  /// 解析完整的 CSV 數據字串
  static List<Map<String, dynamic>> parseCsvData(String csvData) {
    List<Map<String, dynamic>> parsedResults = [];

    // 1. 分割行
    List<String> lines = const LineSplitter().convert(csvData);

    // 2. 遍歷每一行
    for (String line in lines) {
      line = line.trim();
      // 過濾掉非 ASCII 可列印字符 (亂碼)，保留換行
      line = line.replaceAll(RegExp(r'[^\x20-\x7E]'), '');

      if (line.isEmpty) continue;

      // [v13.3 NEW] Structural Recovery: 智能辨識缺少 '$' 的記錄
      // 背景：PacketLogger 雜訊可能覆蓋或切分 '$' 符號，導致合法記錄被誤判
      // 案例：
      //   - ID=10076: ;;;10076;;;;;;... (開頭是 ';')
      //   - ID=10087: P;;;;10087;;;;;;... (開頭是 'P')
      //   - ID=10221: 1;3P;;;;10221;;... (開頭是 '1')
      //
      // 判斷邏輯：即使缺少 '$'，若符合 VLGEO 數據模式，自動補上
      if (!line.startsWith('\$')) {
        // 檢查是否為 VLGEO 數據模式
        List<String> fields = line.split(';');

        // 條件 1：有足夠分號 (VLGEO 標準格式有 33 個欄位，至少 20 個分號)
        if (fields.length >= 20) {
          // 條件 2：TYPE 欄位 [2] 是合法類型
          String typeField = fields.length > 2 ? fields[2].trim() : '';
          // 條件 3：ID 欄位 [6] 是數字
          String idField = fields.length > 6 ? fields[6].trim() : '';
          String idClean = idField.replaceAll(RegExp(r'[^0-9]'), '');

          // 若符合 VLGEO 模式，自動補上 '$'
          if (['1P', '3P', '3D', 'DME', ''].contains(typeField) &&
              idClean.isNotEmpty) {
            line = '\$' + line;
            debugPrint('[STRUCTURAL RECOVERY] 恢復 ID=$idClean');
          } else {
            // 不符合模式，跳過
            continue;
          }
        } else {
          // 分號數量不足，跳過
          continue;
        }
      }

      // [Strict Filter 1] 結構過濾：只接受以 '$' 開頭的資料行
      // 這會自動排除 Header (MARK...), 設定行 (#...), 以及大部分 PacketLogger 雜訊
      // 注意：經過 Structural Recovery 後，合法記錄已補上 '$'
      if (!line.startsWith('\$')) continue;

      // 處理亂碼或非 CSV 內容 (簡單過濾：必須包含分號)
      if (!line.contains(';')) continue;

      List<String> fields = line.split(';');

      // 確保欄位數量足夠 (至少要能讀到 Azimuth 欄位，因為我們要求完整性)
      if (fields.length <= _idxAz) continue;

      // [v13.5+ NEW] 應用 Field Validator (Layer 4 + Layer 5)
      // Layer 4: Context-Aware Letter Filtering (移除數字欄位中的字母)
      // Layer 5: Field-Specific Validation (UTC, 經度, HD, SEQ 驗證)
      fields = BleFieldValidator.validateFields(fields);

      try {
        Map<String, dynamic> record = {};
        Map<String, dynamic> metadata = {};

        // --- [Strict Filter 2] ID 必須存在 ---
        String idStr = fields[_idxId].trim();
        String id = idStr.replaceAll(RegExp(r'[^0-9]'), '');
        if (id.isEmpty) continue;
        record['id'] = id;

        // --- 解析類型 ---
        String type = fields[_idxType].trim();
        record['type'] = type;

        // --- GPS 解析（允許無 GPS 記錄通過）---
        String latStr = fields[_idxLat].trim();
        String ns = fields[_idxNS].trim().toUpperCase();
        String lonStr = fields[_idxLon].trim();
        String ew = fields[_idxEW].trim().toUpperCase();

        bool hasGps = false;
        double lat = 0.0;
        double lon = 0.0;

        if (latStr.isNotEmpty && lonStr.isNotEmpty) {
          lat = double.tryParse(latStr) ?? 0.0;
          lon = double.tryParse(lonStr) ?? 0.0;
          if (lat != 0.0 || lon != 0.0) {
            hasGps = true;
            // 絕對值處理並應用方向
            lat = lat.abs();
            lon = lon.abs();
            if (ns == 'S') lat = -lat;
            if (ew == 'W') lon = -lon;
          }
        }

        record['lat'] = lat;
        record['lon'] = lon;
        metadata['has_gps'] = hasGps;

        // --- 測量數據解析（允許部分欄位為空）---
        // HD 和 AZ 是定位樹木的最低要求，若兩者皆空則跳過

        // 樹高 (H) - 允許為 0 或空
        String hStr = fields[_idxH].trim();
        record['height'] = hStr.isNotEmpty ? double.tryParse(hStr) : 0.0;

        // 水平距離 (HD)
        String hdStr = fields[_idxHD].trim();
        metadata['horizontal_distance'] = hdStr.isNotEmpty ? double.tryParse(hdStr) : 0.0;

        // 斜距 (SD)
        String sdStr = fields[_idxSD].trim();
        metadata['slope_distance'] = sdStr.isNotEmpty ? double.tryParse(sdStr) : 0.0;

        // 俯仰角 (Pitch)
        String pitchStr = fields[_idxPitch].trim();
        metadata['pitch'] = pitchStr.isNotEmpty ? double.tryParse(pitchStr) : 0.0;

        // 方位角 (Azimuth)
        String azStr = fields[_idxAz].trim();
        metadata['azimuth'] = azStr.isNotEmpty ? double.tryParse(azStr) : 0.0;

        // 如果 HD 和 AZ 都是 0 且沒有 GPS，這條記錄無法定位，仍保留但記錄警告
        final hd = metadata['horizontal_distance'] as double? ?? 0.0;
        final az = metadata['azimuth'] as double? ?? 0.0;
        if (hd == 0.0 && az == 0.0 && !hasGps) {
          debugPrint('[BLE] ID=$id: HD=0, AZ=0, 無GPS - 記錄保留但無法定位');
        }

        // [V2 COMPAT] 加入儀器類型到 metadata，供後端 tree_measurement_raw 使用
        // 這樣 V2 batch_import 可以正確寫入 instrument_type 欄位
        if (type.isNotEmpty) {
          metadata['instrument_type'] = type;
        }

        // [V2 COMPAT] 保存原始 GPS 座標到 metadata，供後端備份
        if (hasGps) {
          metadata['raw_lat'] = lat;
          metadata['raw_lon'] = lon;
        }

        // 胸徑 (DIA) - VLGEO2 不具備胸徑測量功能，此欄位永遠為空
        // 需要使用者手動輸入或透過其他儀器測量
        if (fields.length > _idxDia) {
          String diaStr = fields[_idxDia].trim();
          if (diaStr.isNotEmpty) {
            record['dbh'] = double.tryParse(diaStr);
          }
        }

        // 海拔 (Altitude) - 通常有 GPS 就有海拔，但也許可以寬容？
        // 根據 "完整性" 原則，我們也檢查它
        if (fields.length > _idxAlt) {
          String altStr = fields[_idxAlt].trim();
          if (altStr.isNotEmpty) {
            metadata['altitude'] = double.tryParse(altStr);
          }
        }

        if (metadata.isNotEmpty) {
          record['metadata'] = metadata;
        }

        // --- 解析時間 ---
        String dateStr =
            fields[_idxDate].trim().replaceAll(RegExp(r'[^0-9]'), '');
        String timeStr =
            fields[_idxTime].trim().replaceAll(RegExp(r'[^0-9]'), '');

        if (dateStr.length >= 6 && timeStr.length >= 4) {
          try {
            int day = int.parse(dateStr.substring(0, 2));
            int month = int.parse(dateStr.substring(2, 4));
            int year = 2000 + int.parse(dateStr.substring(4, 6));

            int hour = int.parse(timeStr.substring(0, 2));
            int minute = int.parse(timeStr.substring(2, 4));
            int second =
                timeStr.length >= 6 ? int.parse(timeStr.substring(4, 6)) : 0;

            final dateTime = DateTime(year, month, day, hour, minute, second);
            record['timestamp'] = dateTime;
            record['timestamp_iso'] = dateTime.toIso8601String(); // 供後端使用
            
            // [V2 COMPAT] 加入測量時間到 metadata，供後端 tree_measurement_raw 使用
            metadata['measured_at'] = dateTime.toIso8601String();
          } catch (e) {
            debugPrint('Time parse error: $e');
          }
        }

        // 加入結果
        parsedResults.add(record);
      } catch (e) {
        debugPrint('Parsing line error: $line, error: $e');
      }
    }

    return parsedResults;
  }

  /// 處理緩衝區中的亂碼 (如果有的話)
  /// 目前策略：過濾掉非 ASCII 可列印字元 (除了換行符)
  static String cleanReceivedData(String rawData) {
    // 這裡可以加入更複雜的清理邏輯
    // 目前先假設 UTF8 decode 後的字串是可以處理的
    // 如果有 '?'，通常是 decode 失敗的替代字元
    return rawData.replaceAll('', ''); // 移除 Unicode Replacement Character
  }
}
