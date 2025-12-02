import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import '../config/app_config.dart';

/// 樹種辨識服務
/// 整合 Pl@ntNet、GBIF、iNaturalist 等開源 API
class SpeciesIdentificationService {
  static String get baseUrl => AppConfig().baseUrl;

  /// 上傳圖片進行樹種辨識
  /// [imageFile] - 圖片檔案
  /// [organ] - 器官類型: leaf(葉), flower(花), fruit(果), bark(樹皮), auto(自動)
  /// [lang] - 語言: zh(中文), en(英文)
  static Future<Map<String, dynamic>> identifyFromFile(
    File imageFile, {
    String organ = 'auto',
    String lang = 'zh',
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      return identifyFromBytes(bytes, organ: organ, lang: lang);
    } catch (e) {
      return {
        'success': false,
        'error': '讀取圖片失敗: $e',
      };
    }
  }

  /// 從 bytes 進行辨識（適用於相機拍攝）
  static Future<Map<String, dynamic>> identifyFromBytes(
    Uint8List imageBytes, {
    String organ = 'auto',
    String lang = 'zh',
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/species/identify'),
      );

      // 明確設定 content-type 為 image/jpeg
      request.files.add(http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: 'plant_image.jpg',
        contentType: MediaType('image', 'jpeg'),
      ));

      request.fields['organ'] = organ;
      request.fields['lang'] = lang;

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
      );

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'error': errorData['error'] ?? '辨識服務發生錯誤',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': '連線逾時或網路錯誤: $e',
      };
    }
  }

  /// 搜尋物種（使用 iNaturalist）
  static Future<Map<String, dynamic>> searchSpecies(String query) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/species/search?q=${Uri.encodeComponent(query)}'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {
          'success': false,
          'error': '搜尋失敗',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': '連線錯誤: $e',
      };
    }
  }

  /// 從 GBIF 取得物種詳細資訊
  static Future<Map<String, dynamic>> getGBIFSpecies(String scientificName) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/species/gbif/${Uri.encodeComponent(scientificName)}'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {
          'success': false,
          'error': 'GBIF 查詢失敗',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': '連線錯誤: $e',
      };
    }
  }

  /// 從 iNaturalist 取得物種詳細資訊
  static Future<Map<String, dynamic>> getINaturalistSpecies(int taxonId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/species/inaturalist/$taxonId'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {
          'success': false,
          'error': 'iNaturalist 查詢失敗',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': '連線錯誤: $e',
      };
    }
  }

  /// 檢查辨識服務狀態
  static Future<Map<String, dynamic>> checkServiceStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/species/status'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {
          'success': false,
          'error': '無法取得服務狀態',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': '連線錯誤: $e',
      };
    }
  }

  /// 器官類型對照表（用於 UI 顯示）
  static Map<String, String> get organTypes => {
    'auto': '自動辨識',
    'leaf': '葉片',
    'flower': '花朵',
    'fruit': '果實',
    'bark': '樹皮',
  };

  /// 取得器官類型的圖示
  static String getOrganIcon(String organ) {
    switch (organ) {
      case 'leaf':
        return '🍃';
      case 'flower':
        return '🌸';
      case 'fruit':
        return '🍎';
      case 'bark':
        return '🪵';
      default:
        return '🌿';
    }
  }
}
