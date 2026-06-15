import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'ble_field_validator.dart';
import '../utils/utm_converter.dart';

class BleDataProcessor {
  // CSV 欄位索引 (基於 DATA_2.CSV)
  static const int _idxType = 2;
  static const int _idxProd = 3;  // PROD (Product Code)
  static const int _idxVer = 4;   // VER (Firmware Version)
  static const int _idxSnr = 5;   // SNR (Serial Number)
  static const int _idxId = 6;
  static const int _idxTrph = 8;  // TRPH (胸高, 通常 1.3m)
  static const int _idxRefh = 9;  // REFH (參考高)
  static const int _idxPoff = 10; // P.OFF (棱鏡偏移)
  static const int _idxDecl = 11; // DECL (磁偏角)
  static const int _idxLat = 12;
  static const int _idxNS = 13;
  static const int _idxLon = 14;
  static const int _idxEW = 15;
  static const int _idxAlt = 16; // Altitude
  static const int _idxHdop = 17; // HDOP (GPS 品質指標)
  static const int _idxDate = 18;
  static const int _idxTime = 19;
  static const int _idxSeq = 20; // SEQ (測量序號)
  static const int _idxArea = 21; // AREA (基底面積/橫斷面)
  static const int _idxVol = 22; // VOL (體積)
  static const int _idxSD = 23; // Slope Distance
  static const int _idxHD = 24; // Horizontal Distance
  static const int _idxH = 25; // Height
  static const int _idxDia = 26; // Diameter
  static const int _idxPitch = 27; // Pitch/Inclination
  static const int _idxAz = 28; // Azimuth
  static const int _idxX = 29; // X(m) - UTM Easting
  static const int _idxY = 30; // Y(m) - UTM Northing
  static const int _idxZ = 31; // Z(m) - UTM Elevation
  static const int _idxUtmZone = 32; // UTM ZONE

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
            line = '\$$line';
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

        // --- [Strict Filter 3] GPS 解析（允許無 GPS）---
        String latStr = fields[_idxLat].trim();
        String ns = fields[_idxNS].trim().toUpperCase();
        String lonStr = fields[_idxLon].trim();
        String ew = fields[_idxEW].trim().toUpperCase();

        double lat = 0.0;
        double lon = 0.0;
        bool hasGps = false;

        if (latStr.isNotEmpty && lonStr.isNotEmpty) {
          lat = double.tryParse(latStr) ?? 0.0;
          lon = double.tryParse(lonStr) ?? 0.0;
          if (lat != 0.0 || lon != 0.0) {
            hasGps = true;
          }
        }

        if (hasGps) {
          lat = lat.abs();
          lon = lon.abs();
          if (ns == 'S') lat = -lat;
          if (ew == 'W') lon = -lon;
        }

        record['lat'] = lat;
        record['lon'] = lon;
        record['hasGps'] = hasGps;

        // --- [Strict Filter 4] 只要有 HD（或 SD）+ AZ 就保留 ---
        String hdStr = fields[_idxHD].trim();
        String sdStr = fields[_idxSD].trim();
        String azStr = fields[_idxAz].trim();

        double? hd = hdStr.isNotEmpty ? double.tryParse(hdStr) : null;
        double? sd = sdStr.isNotEmpty ? double.tryParse(sdStr) : null;
        double? az = azStr.isNotEmpty ? double.tryParse(azStr) : null;

        if ((hd == null && sd == null) || az == null) continue;

        metadata['horizontal_distance'] = hd ?? sd;
        metadata['slope_distance'] = sd;
        metadata['azimuth'] = az;

        String hStr = fields[_idxH].trim();
        record['height'] = hStr.isNotEmpty ? double.tryParse(hStr) : null;

        String pitchStr = fields[_idxPitch].trim();
        metadata['pitch'] = pitchStr.isNotEmpty ? double.tryParse(pitchStr) : null;

        // SEQ 欄位
        String seqStr = fields[_idxSeq].trim();
        int seq = int.tryParse(seqStr) ?? 1;
        record['seq'] = seq;

        // [v21.0] AREA / VOL - 林業基底面積與體積測量
        // 儀器 BAF (Basal Area Factor) 模式或體積測量模式才有值
        if (fields.length > _idxArea) {
          String areaStr = fields[_idxArea].trim();
          if (areaStr.isNotEmpty) {
            final v = double.tryParse(areaStr);
            if (v != null) metadata['area'] = v;
          }
        }
        if (fields.length > _idxVol) {
          String volStr = fields[_idxVol].trim();
          if (volStr.isNotEmpty) {
            final v = double.tryParse(volStr);
            if (v != null) metadata['volume'] = v;
          }
        }

        // [V2 COMPAT] 加入儀器類型到 metadata，供後端 tree_measurement_raw 使用
        // 這樣 V2 batch_import 可以正確寫入 instrument_type 欄位
        if (type.isNotEmpty) {
          metadata['instrument_type'] = type;
        }

        // [V2 COMPAT] 保存原始 GPS 座標到 metadata，供後端備份
        metadata['raw_lat'] = lat;
        metadata['raw_lon'] = lon;

        // [v19.0] HDOP - GPS 精度指標 (值越小精度越高，一般 <2 為良好)
        if (fields.length > _idxHdop) {
          String hdopStr = fields[_idxHdop].trim();
          if (hdopStr.isNotEmpty) {
            metadata['hdop'] = double.tryParse(hdopStr);
          }
        }

        // [v19.0] 儀器設備資訊 (PROD, VER, SNR)
        if (fields.length > _idxSnr) {
          String snrStr = fields[_idxSnr].trim();
          if (snrStr.isNotEmpty) metadata['device_sn'] = snrStr;
        }
        if (fields.length > _idxProd) {
          String prodStr = fields[_idxProd].trim();
          if (prodStr.isNotEmpty) metadata['product_code'] = prodStr;
        }
        if (fields.length > _idxVer) {
          String verStr = fields[_idxVer].trim();
          if (verStr.isNotEmpty) metadata['firmware_version'] = verStr;
        }

        // [v19.0] 儀器校準參數 (TRPH, REFH, P.OFF, DECL)
        // TRPH: 胸高 (通常 1.3m，林業標準)
        // REFH: 儀器參考高度
        // P.OFF: 棱鏡偏移量
        // DECL: 磁偏角
        if (fields.length > _idxTrph) {
          String trphStr = fields[_idxTrph].trim();
          if (trphStr.isNotEmpty) {
            final trph = double.tryParse(trphStr);
            metadata['trph'] = trph;
            // [v21.0] G5: TRPH ≠ 1.3m 警示（台灣林業標準胸高 1.3m）
            // 不阻擋匯入、不修改 DBH，只標旗供 UI 統計提示
            if (trph != null && (trph - 1.3).abs() > 0.01) {
              metadata['trph_warning'] = true;
            }
          }
        }
        if (fields.length > _idxRefh) {
          String refhStr = fields[_idxRefh].trim();
          if (refhStr.isNotEmpty) metadata['ref_height'] = double.tryParse(refhStr);
        }
        if (fields.length > _idxPoff) {
          String poffStr = fields[_idxPoff].trim();
          if (poffStr.isNotEmpty) metadata['prism_offset'] = double.tryParse(poffStr);
        }
        if (fields.length > _idxDecl) {
          String declStr = fields[_idxDecl].trim();
          if (declStr.isNotEmpty) {
            final decl = double.tryParse(declStr);
            metadata['declination'] = decl;
            // [v21.0] G2: DECL warn-only（手冊 §5.2 儀器自動套用，app 不重算 AZ）
            // 標記儀器已套用，並對較大 DECL 提示使用者確認儀器設定
            metadata['declination_applied_by_instrument'] = true;
            if (decl != null && decl.abs() > 1.0) {
              metadata['decl_warning'] = true;
            }
          }
        }

        // 胸徑 (DIA) - Remote Diameter 功能
        // Settings → REMOTE DIAMETER 啟用後，儀器可遠距測量直徑（精度 10m@1.2cm）
        // 未啟用時此欄位為空，需透過影像 DBH 或手動輸入補測
        if (fields.length > _idxDia) {
          String diaStr = fields[_idxDia].trim();
          if (diaStr.isNotEmpty) {
            double? dia = double.tryParse(diaStr);
            if (dia != null && dia > 0) {
              record['dbh'] = dia;
              metadata['dbh_source'] = 'remote_diameter';
            }
          }
        }

        // 海拔 (Altitude)
        if (fields.length > _idxAlt) {
          String altStr = fields[_idxAlt].trim();
          if (altStr.isNotEmpty) {
            metadata['altitude'] = double.tryParse(altStr);
          }
        }

        // [v19.0] UTM 座標 (X, Y, Z, UTM ZONE) - 可作為 GPS 交叉驗證或補救
        if (fields.length > _idxUtmZone) {
          String xStr = fields[_idxX].trim();
          String yStr = fields[_idxY].trim();
          String zStr = fields[_idxZ].trim();
          String utmZone = fields[_idxUtmZone].trim();
          if (xStr.isNotEmpty) metadata['utm_x'] = double.tryParse(xStr);
          if (yStr.isNotEmpty) metadata['utm_y'] = double.tryParse(yStr);
          if (zStr.isNotEmpty) metadata['utm_z'] = double.tryParse(zStr);
          if (utmZone.isNotEmpty) metadata['utm_zone'] = utmZone;

          // [v20.0] UTM → WGS84 GPS 補救：無 GPS 但有 UTM 時自動反算
          if (!hasGps) {
            final recovered = UtmConverter.fromVlgeo2Metadata(
              utmX: metadata['utm_x'] as double?,
              utmY: metadata['utm_y'] as double?,
              utmZone: metadata['utm_zone'] as String?,
            );
            if (recovered != null) {
              lat = recovered.lat;
              lon = recovered.lon;
              hasGps = true;
              record['lat'] = lat;
              record['lon'] = lon;
              record['hasGps'] = true;
              metadata['gps_source'] = 'utm_recovery';
              metadata['raw_lat'] = lat;
              metadata['raw_lon'] = lon;
              debugPrint('[UTM RECOVERY] ID=$id: UTM(${metadata['utm_x']}, '
                  '${metadata['utm_y']}, $utmZone) → GPS($lat, $lon)');
            }
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

  /// 合併多 SEQ 記錄（順序無關）
  ///
  /// 3P 合併：同 ID 且 HD/AZ 相同 -> 淨樹高 = max(H) - min(H)
  /// 1P 合併：同 ID 但 HD/AZ 不同 -> 取最後一個 SEQ
  static List<Map<String, dynamic>> mergeMultiSeqRecords(
    List<Map<String, dynamic>> records,
  ) {
    final Map<String, List<Map<String, dynamic>>> groupById = {};
    for (final r in records) {
      final id = r['id']?.toString() ?? '';
      groupById.putIfAbsent(id, () => []).add(r);
    }

    final List<Map<String, dynamic>> merged = [];

    for (final entry in groupById.entries) {
      final group = entry.value;
      if (group.length == 1) {
        merged.add(group.first);
        continue;
      }

      final type = group.first['type']?.toString() ?? '';
      final meta0 = group.first['metadata'] as Map<String, dynamic>? ?? {};
      final hd0 = (meta0['horizontal_distance'] as num?)?.toDouble();
      final az0 = (meta0['azimuth'] as num?)?.toDouble();

      // [v21.0] 3P 合併容差：HD ±0.05m / AZ ±0.5° 視為同站位
      // 因儀器讀數有抖動，嚴格相等會誤判為 1P
      const double hdTolerance = 0.05;
      const double azTolerance = 0.5;
      bool allSameHdAz = group.every((r) {
        final m = r['metadata'] as Map<String, dynamic>? ?? {};
        final hd = (m['horizontal_distance'] as num?)?.toDouble();
        final az = (m['azimuth'] as num?)?.toDouble();
        if (hd0 == null || az0 == null || hd == null || az == null) return false;
        return (hd - hd0).abs() <= hdTolerance && (az - az0).abs() <= azTolerance;
      });

      if (type == '3P' && allSameHdAz) {
        // 3P 三點測高合併：淨樹高 = max(H) - min(H)
        final hValues = group
            .map((r) => (r['height'] as num?)?.toDouble())
            .whereType<double>()
            .toList();

        if (hValues.length >= 2) {
          final maxH = hValues.reduce((a, b) => a > b ? a : b);
          final minH = hValues.reduce((a, b) => a < b ? a : b);
          final netHeight = maxH - minH;

          final base = Map<String, dynamic>.from(group.first);
          base['height'] = netHeight;
          final baseMeta = Map<String, dynamic>.from(
              base['metadata'] as Map<String, dynamic>? ?? {});
          baseMeta['raw_h_values'] = hValues;
          baseMeta['merge_method'] = '3P_max_min';

          // [v21.0] C1: 3P 站位漂移檢查（手冊 §5.4 三點應同站位）
          // 計算三筆 lat/lon 的最大兩兩距離，>5m 標警告
          final coords = group
              .where((r) => r['lat'] is num && r['lon'] is num)
              .map((r) => [
                    (r['lat'] as num).toDouble(),
                    (r['lon'] as num).toDouble()
                  ])
              .where((c) => c[0] != 0 || c[1] != 0)
              .toList();
          if (coords.length >= 2) {
            double maxDrift = 0;
            for (int i = 0; i < coords.length; i++) {
              for (int j = i + 1; j < coords.length; j++) {
                final d = _haversineMeters(
                    coords[i][0], coords[i][1], coords[j][0], coords[j][1]);
                if (d > maxDrift) maxDrift = d;
              }
            }
            baseMeta['pos_drift_m'] = double.parse(maxDrift.toStringAsFixed(2));
            if (maxDrift > 5.0) {
              baseMeta['pos_drift_warning'] = true;
            }
          }

          base['metadata'] = baseMeta;
          base['seq'] = 1;

          debugPrint('[SEQ MERGE] 3P ID=${entry.key}: '
              'H values=$hValues -> net=$netHeight');
          merged.add(base);
        } else {
          merged.add(group.last);
        }
      } else {
        // 1P 或 HD/AZ 不同：取最後一個 SEQ，但保留所有 SEQ 資料
        group.sort((a, b) =>
            ((a['seq'] as int?) ?? 1).compareTo((b['seq'] as int?) ?? 1));
        final last = Map<String, dynamic>.from(group.last);

        // 保留所有 SEQ 的完整資料到 metadata，避免資料遺失
        final lastMeta = Map<String, dynamic>.from(
            last['metadata'] as Map<String, dynamic>? ?? {});
        lastMeta['merge_method'] = '1P_keep_last';
        lastMeta['total_seq_count'] = group.length;
        lastMeta['all_seq_data'] = group.map((r) {
          final m = r['metadata'] as Map<String, dynamic>? ?? {};
          return {
            'seq': r['seq'],
            'lat': r['lat'],
            'lon': r['lon'],
            'height': r['height'],
            'horizontal_distance': m['horizontal_distance'],
            'slope_distance': m['slope_distance'],
            'azimuth': m['azimuth'],
            'pitch': m['pitch'],
            'altitude': m['altitude'],
          };
        }).toList();
        last['metadata'] = lastMeta;

        debugPrint('[SEQ MERGE] $type ID=${entry.key}: '
            '${group.length} SEQ, keep last SEQ=${last['seq']} (all SEQ preserved in metadata)');
        merged.add(last);
      }
    }

    debugPrint('[SEQ MERGE] ${records.length} records -> ${merged.length} merged');
    return merged;
  }

  /// 處理緩衝區中的亂碼 (如果有的話)
  /// 目前策略：過濾掉非 ASCII 可列印字元 (除了換行符)
  static String cleanReceivedData(String rawData) {
    // 這裡可以加入更複雜的清理邏輯
    // 目前先假設 UTF8 decode 後的字串是可以處理的
    // 如果有 '?'，通常是 decode 失敗的替代字元
    return rawData.replaceAll('', ''); // 移除 Unicode Replacement Character
  }

  /// [v21.0] Haversine 距離（公尺）— 用於 3P 站位漂移、session 內 GPS 跳變偵測
  static double _haversineMeters(
      double lat1, double lon1, double lat2, double lon2) {
    const double r = 6371000; // 地球半徑（公尺）
    const double deg2rad = math.pi / 180.0;
    final double dLat = (lat2 - lat1) * deg2rad;
    final double dLon = (lon2 - lon1) * deg2rad;
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * deg2rad) *
            math.cos(lat2 * deg2rad) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }
}
