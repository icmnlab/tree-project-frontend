import 'package:flutter/foundation.dart';

/// 現場連線單次量測（MEMORY 關 + 按 SEND）。
///
/// 實機 VLGEO2_3190 經 BLE 送出的是手冊 §9.2 NMEA `$PHGF,HVV,...` 文字
/// （20+20+15 byte 分片），不是 §9.3 固定 20-byte 二進位格式。
class BleLiveMeasurement {
  final String messageId;
  final String dataType;
  final double horizontalDistanceM;
  final String horizontalDistanceUnit;
  final double azimuthDeg;
  final String azimuthUnit;
  final double pitchDeg;
  final String pitchUnit;
  final double slopeDistanceM;
  final String slopeDistanceUnit;
  final double heightM;
  final String heightUnit;
  /// Geo2 V3.7+ NMEA 擴充欄（手冊 §9.2 僅 12 欄；實機第 13–14 欄為 Remote Diameter）。
  /// `CM` = 公分；`0.0,CM` = 未量遠距直徑，對應 CSV 空白 `DIA` 欄。
  final double? trailingValue;
  final String? trailingUnit;
  final String? checksum;
  final String rawNmea;
  final Map<String, dynamic> rawFields;

  const BleLiveMeasurement({
    required this.messageId,
    required this.dataType,
    required this.horizontalDistanceM,
    required this.horizontalDistanceUnit,
    required this.azimuthDeg,
    required this.azimuthUnit,
    required this.pitchDeg,
    required this.pitchUnit,
    required this.slopeDistanceM,
    required this.slopeDistanceUnit,
    required this.heightM,
    required this.heightUnit,
    this.trailingValue,
    this.trailingUnit,
    this.checksum,
    required this.rawNmea,
    required this.rawFields,
  });

  /// 儀器 Remote Diameter（cm）；未量或為 0 時為 null。
  double? get remoteDiameterCm {
    if (trailingUnit != 'CM') return null;
    final v = trailingValue;
    if (v == null || v <= 0) return null;
    return v;
  }

  Map<String, dynamic> toBleRecordMap({
    required String id,
    required double lat,
    required double lon,
    required bool hasGps,
    String gpsSource = 'surveyor',
    Map<String, dynamic>? extraMetadata,
  }) {
    final remoteDia = remoteDiameterCm;

    return {
      'id': id,
      'type': 'LIVE',
      'lat': lat,
      'lon': lon,
      'hasGps': hasGps,
      'height': heightM,
      if (remoteDia != null) 'dbh': remoteDia,
      'metadata': {
        'gps_source': gpsSource,
        'horizontal_distance': horizontalDistanceM,
        'slope_distance': slopeDistanceM,
        'pitch': pitchDeg,
        'azimuth': azimuthDeg,
        'ble_mode': 'live_nmea_phgf',
        'nmea_message_id': messageId,
        'nmea_data_type': dataType,
        'hd_unit': horizontalDistanceUnit,
        'az_unit': azimuthUnit,
        'pitch_unit': pitchUnit,
        'sd_unit': slopeDistanceUnit,
        'height_unit': heightUnit,
        if (trailingValue != null) 'trailing_value': trailingValue,
        if (trailingUnit != null) 'trailing_unit': trailingUnit,
        if (remoteDia != null) ...{
          'remote_diameter_cm': remoteDia,
          'dbh_source': 'remote_diameter',
        },
        if (checksum != null) 'nmea_checksum': checksum,
        'raw_nmea': rawNmea,
        'raw_fields': rawFields,
        ...?extraMetadata,
      },
    };
  }
}

/// 累積 BLE notify 分片，重組完整 NMEA 句。
///
/// 實機第二棵起常見：手冊 §9.3 的 20-byte ASCII 前綴與 `$PHGF` 黏在同一 notify、
/// 無 CR/LF，僅靠換行切割會漏句。
class BleLiveNmeaAssembler {
  final StringBuffer _buffer = StringBuffer();
  final List<BleLiveMeasurement> _pending = [];
  int _lastPhgfEnd = 0;

  static final RegExp _phgfSentence = RegExp(
    r'\$PHGF,HVV,[^*]+\*[0-9A-Fa-f]{2}',
  );

  List<BleLiveMeasurement> feed(List<int> data) {
    if (data.isEmpty) return const [];

    final chunk = String.fromCharCodes(
      data.where((b) => b == 0x0D || b == 0x0A || (b >= 0x20 && b <= 0x7E)),
    );
    if (chunk.isEmpty) return const [];

    _buffer.write(chunk);
    final text = _buffer.toString();

    _pending.clear();

    for (final match in _phgfSentence.allMatches(text)) {
      if (match.end <= _lastPhgfEnd) continue;
      final line = match.group(0);
      if (line == null) continue;
      final m = BleLiveNmeaParser.tryParseLine(line);
      if (m != null) {
        _pending.add(m);
        _lastPhgfEnd = match.end;
      }
    }

    // 保留未完成的尾部（含可能半截的 $PHGF 或 §9.3 前綴）
    if (_lastPhgfEnd > 0) {
      final tail = text.substring(_lastPhgfEnd);
      _buffer
        ..clear()
        ..write(tail);
      _lastPhgfEnd = 0;
    } else if (text.length > 512) {
      // 長時間無 PHGF 時避免緩衝無限增長
      _buffer
        ..clear()
        ..write(text.substring(text.length - 256));
    }

    // 仍支援以 CR/LF 結束的 GPS 等其它 NMEA（§10 / §4.6.2）
    final tailText = _buffer.toString();
    if (tailText.contains('\n') || tailText.contains('\r')) {
      final lines = tailText.split(RegExp(r'\r?\n'));
      _buffer.clear();
      if (lines.isNotEmpty &&
          !chunk.endsWith('\n') &&
          !chunk.endsWith('\r')) {
        _buffer.write(lines.removeLast());
      }
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('\$PHGF')) continue;
        // GPS 等非 PHGF 句留給上層若需擴充；現場連線主路徑為 PHGF
      }
    }

    return List.unmodifiable(_pending);
  }

  void reset() {
    _buffer.clear();
    _pending.clear();
    _lastPhgfEnd = 0;
  }
}

class BleLiveNmeaParser {
  static BleLiveMeasurement? tryParseLine(String line) {
    if (!line.startsWith('\$PHGF')) return null;

    final parts = line.split(',');
    if (parts.length < 12) return null;

    try {
      final hd = double.parse(parts[2]);
      final az = double.parse(parts[4]);
      final pitch = double.parse(parts[6]);
      final sd = double.parse(parts[8]);
      final h = double.parse(parts[10]);

      double? trailing;
      String? trailingUnit;
      String? checksum;

      if (parts.length > 12 && parts[12].trim().isNotEmpty) {
        trailing = double.tryParse(parts[12]);
      }
      if (parts.length > 13) {
        trailingUnit = parts[13].trim();
      }
      if (parts.length > 14) {
        checksum = parts[14].trim();
      }

      final rawFields = <String, dynamic>{
        for (var i = 0; i < parts.length; i++) 'field_$i': parts[i],
        'parts_count': parts.length,
      };

      return BleLiveMeasurement(
        messageId: parts[0].replaceFirst('\$', ''),
        dataType: parts[1],
        horizontalDistanceM: hd,
        horizontalDistanceUnit: parts[3],
        azimuthDeg: az,
        azimuthUnit: parts[5],
        pitchDeg: pitch,
        pitchUnit: parts[7],
        slopeDistanceM: sd,
        slopeDistanceUnit: parts[9],
        heightM: h,
        heightUnit: parts[11],
        trailingValue: trailing,
        trailingUnit: trailingUnit,
        checksum: checksum,
        rawNmea: line,
        rawFields: rawFields,
      );
    } catch (e) {
      debugPrint('[BleLiveNmeaParser] failed: $e line=$line');
      return null;
    }
  }
}

/// 向後相容：勿再將 NMEA 分片誤判為 §9.3。
class BleLivePacketDecoder {
  @Deprecated('Use BleLiveNmeaAssembler + BleLiveNmeaParser')
  static BleLiveMeasurement? tryParse(List<int> data) {
    if (data.length != 20) return null;
    final rawAscii = String.fromCharCodes(data);
    if (rawAscii.contains(',') || rawAscii.contains('\$')) return null;
    // 保留舊 §9.3 路徑供未來若遇到純 20-byte 韌體
    try {
      final hd = int.parse(rawAscii.substring(0, 4).trim()) / 10.0;
      final sd = int.parse(rawAscii.substring(4, 8).trim()) / 10.0;
      final h = int.parse(rawAscii.substring(8, 12).trim()) / 10.0;
      final pitch = int.parse(rawAscii.substring(12, 16).trim()) / 10.0;
      final az = int.parse(rawAscii.substring(16, 20).trim()) / 10.0;
      return BleLiveMeasurement(
        messageId: 'PHGF',
        dataType: 'HVV',
        horizontalDistanceM: hd,
        horizontalDistanceUnit: 'M',
        azimuthDeg: az,
        azimuthUnit: 'D',
        pitchDeg: pitch,
        pitchUnit: 'D',
        slopeDistanceM: sd,
        slopeDistanceUnit: 'M',
        heightM: h,
        heightUnit: 'M',
        rawNmea: rawAscii,
        rawFields: {'legacy_v93_ascii': rawAscii},
      );
    } catch (_) {
      return null;
    }
  }
}
