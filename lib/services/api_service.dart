import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart'; // Import AppConfig
import '../config/global_keys.dart'; // Import GlobalKeys
import 'auth_service.dart'; // Import AuthService

class ApiService {
  // The baseUrl is now dynamically retrieved from AppConfig
  static String get baseUrl => AppConfig().baseUrl;
  static String? _jwtToken;
  static const String _jwtTokenKey = 'auth_jwt_token';
  static const _secureStorage = FlutterSecureStorage();

  static Future<void> initialize() async {
    try {
      final raw = await _secureStorage.read(key: _jwtTokenKey);
      // [HOTFIX] Android keystore may silently return garbled bytes after
      // reinstall / keystore reset (no exception thrown). Validate before use:
      // a real JWT is pure ASCII printable + 3 dot-separated base64url segments.
      if (raw != null && _isValidJwt(raw)) {
        _jwtToken = raw;
      } else {
        _jwtToken = null;
        if (raw != null) {
          // Corrupted entry — wipe it so next launch is clean.
          try {
            await _secureStorage.delete(key: _jwtTokenKey);
          } catch (_) {}
        }
      }
    } catch (e) {
      // flutter_secure_storage may fail with BadPaddingException after
      // reinstall / keystore reset. Clear the corrupted entry and continue so
      // the app can still render the login screen instead of hanging on a
      // black screen.
      _jwtToken = null;
      try {
        await _secureStorage.delete(key: _jwtTokenKey);
      } catch (_) {
        // As a last resort wipe everything this plugin stored for us.
        try {
          await _secureStorage.deleteAll();
        } catch (_) {}
      }
    }
  }

  // [HOTFIX] JWT format check: 3 segments separated by '.', each base64url ASCII
  static bool _isValidJwt(String token) {
    if (token.isEmpty) return false;
    // Authorization header values must be printable ASCII (0x20-0x7E) + tab.
    for (final code in token.codeUnits) {
      if (code != 0x09 && (code < 0x20 || code > 0x7E)) return false;
    }
    final parts = token.split('.');
    if (parts.length != 3) return false;
    final base64urlRe = RegExp(r'^[A-Za-z0-9_\-]+=*$');
    return parts.every((p) => p.isNotEmpty && base64urlRe.hasMatch(p));
  }

  static Future<void> setJwtToken(String? token) async {
    if (token == null || token.isEmpty) {
      _jwtToken = null;
      await _secureStorage.delete(key: _jwtTokenKey);
      return;
    }

    if (!_isValidJwt(token)) {
      // Refuse to persist malformed token; treat as logged-out.
      _jwtToken = null;
      await _secureStorage.delete(key: _jwtTokenKey);
      return;
    }

    _jwtToken = token;
    await _secureStorage.write(key: _jwtTokenKey, value: token);
  }

  static String? getJwtToken() {
    return _jwtToken;
  }

  static Map<String, String> getAuthHeaders() {
    final headers = <String, String>{};

    if (_jwtToken != null && _jwtToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_jwtToken';
    }

    return headers;
  }

  // Fetch ML Service Config from Backend
  static Future<void> fetchMlServiceConfig() async {
    try {
      final response = await get('ml-service/status');
      if (response['success'] == true && response['configured'] == true) {
        final String? url = response['ml_service_url'];
        final String? apiKey = response['ml_api_key'];
        
        if (url != null) {
          await AppConfig().setSelfHostedMlUrl(url);
          await AppConfig().setMlApiKey(apiKey);
          print('[ApiService] Successfully updated ML config from backend: $url');
        }
      }
    } catch (e) {
      print('[ApiService] Failed to fetch ML config: $e');
    }
  }

  static const _timeout = Duration(seconds: 30);

  // HTTP GET 請求
  static Future<Map<String, dynamic>> get(String endpoint) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/$endpoint'),
        headers: _getHeaders(),
      ).timeout(_timeout);

      return _handleResponse(response);
    } catch (e) {
      return {
        'success': false,
        'message': '請求發生錯誤: $e',
      };
    }
  }

  // HTTP POST 請求
  static Future<Map<String, dynamic>> post(
      String endpoint, dynamic data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/$endpoint'),
        headers: _getHeaders(),
        body: json.encode(data),
      ).timeout(_timeout);

      return _handleResponse(response);
    } catch (e) {
      return {
        'success': false,
        'message': '請求發生錯誤: $e',
      };
    }
  }

  // HTTP PUT 請求
  static Future<Map<String, dynamic>> put(String endpoint, dynamic data) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/$endpoint'),
        headers: _getHeaders(),
        body: json.encode(data),
      ).timeout(_timeout);

      return _handleResponse(response);
    } catch (e) {
      return {
        'success': false,
        'message': '請求發生錯誤: $e',
      };
    }
  }

  // HTTP PATCH 請求
  static Future<Map<String, dynamic>> patch(String endpoint, dynamic data) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/$endpoint'),
        headers: _getHeaders(),
        body: json.encode(data),
      ).timeout(_timeout);

      return _handleResponse(response);
    } catch (e) {
      return {
        'success': false,
        'message': '請求發生錯誤: $e',
      };
    }
  }

  // HTTP DELETE 請求
  static Future<Map<String, dynamic>> delete(String endpoint) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/$endpoint'),
        headers: _getHeaders(),
      ).timeout(_timeout);

      return _handleResponse(response);
    } catch (e) {
      return {
        'success': false,
        'message': '請求發生錯誤: $e',
      };
    }
  }

  // 觸發後端清理任務
  // [FIX] 加 throttle：清理是維護用工具，不應在每個畫面切換都打。
  // 同 App 一次啟動內，10 分鐘最多打一次。避免被 nginx rate limit (api zone, 30r/m) 擋掉造成 503。
  static DateTime? _lastCleanupAt;
  static Future<void> triggerCleanup() async {
    final now = DateTime.now();
    if (_lastCleanupAt != null &&
        now.difference(_lastCleanupAt!).inMinutes < 10) {
      return; // 靜默略過
    }
    _lastCleanupAt = now;
    try {
      // 這是一個 "fire-and-forget" 的請求，我們不在乎它的回應
      // 只需要確保請求被發送即可
      await http.post(
        Uri.parse('$baseUrl/project_areas/cleanup'),
        headers: _getHeaders(),
      ).timeout(_timeout);
      print('[ApiService] Cleanup process triggered.');
    } catch (e) {
      // 即使失敗了也不需要打斷使用者操作，只需在控制台記錄即可
      print('[ApiService] Failed to trigger cleanup process: $e');
    }
  }

  // 處理 HTTP 響應
  static Map<String, dynamic> _handleResponse(http.Response response) {
    // 處理 401 Unauthorized
    if (response.statusCode == 401) {
      AuthService.clearSession();
      GlobalKeys.navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (route) => false);
      
      return {
        'success': false,
        'message': '認證失效，請重新登入',
      };
    }

    // 當我們看到成功登入/有新 token，就去抓取最新的 ML 網址
    if (response.request?.url.path.endsWith('/login') == true && response.statusCode == 200) {
      // 在背景更新，不卡住登入流程
      Future.microtask(() => ApiService.fetchMlServiceConfig());
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        return json.decode(response.body);
      } catch (e) {
        return {
          'success': true,
          'data': response.body,
        };
      }
    } else {
      try {
        return json.decode(response.body);
      } catch (e) {
        return {
          'success': false,
          'message': '請求失敗 (${response.statusCode}): ${response.body}',
        };
      }
    }
  }

  // 獲取請求頭
  static Map<String, String> _getHeaders() {
    return {
      'Content-Type': 'application/json',
      ...getAuthHeaders(),
    };
  }

  Future<List<Map<String, dynamic>>> fetchTreeSurveyData() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/tree_survey'),
        headers: _getHeaders(),
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
      return [];
    } catch (e) {
      print('Error fetching tree data: $e');
      return [];
    }
  }

  // [Stage 0.3] 已移除 getTreeSpecies()：
  //   後端 /carbon-sink/tree-species 路由隨 tree_carbon_data 表刪除一同移除，
  //   實際上本函數只被 CarbonSinkService.initialize() 預載使用，未被任何画面使用。

  // AI永續碳匯助手 - 計算特定樹種的碳吸收量
  static Future<Map<String, dynamic>> calculateSpeciesCarbon({
    String? speciesId,
    String? speciesName,
    double? age,
    double? dbh,
    double? height,
  }) async {
    Map<String, String> queryParams = {};

    if (speciesId != null) queryParams['speciesId'] = speciesId;
    if (speciesName != null) queryParams['speciesName'] = speciesName;
    if (age != null) queryParams['age'] = age.toString();
    if (dbh != null) queryParams['dbh'] = dbh.toString();
    if (height != null) queryParams['height'] = height.toString();

    final endpoint =
        'carbon-sink/species?${_encodeQueryParameters(queryParams)}';
    return get(endpoint);
  }

  // AI永續碳匯助手 - 計算總碳吸收量
  static Future<Map<String, dynamic>> calculateTotalCarbon(
      List<Map<String, dynamic>> trees) async {
    return post('carbon-sink/calculate', {'trees': trees});
  }

  // AI永續碳匯助手 - 根據地區推薦適合樹種
  static Future<Map<String, dynamic>> recommendByRegion({
    required String region,
    String? purpose,
    int? limit,
  }) async {
    Map<String, String> queryParams = {'region': region};

    if (purpose != null) queryParams['purpose'] = purpose;
    if (limit != null) queryParams['limit'] = limit.toString();

    final endpoint =
        'carbon-sink/recommend-by-region?${_encodeQueryParameters(queryParams)}';
    return get(endpoint);
  }

  // AI永續碳匯助手 - 依碳吸收效率篩選樹種
  static Future<Map<String, dynamic>> filterByEfficiency({
    String? efficiency,
    String? growthRate,
    int? limit,
  }) async {
    Map<String, String> queryParams = {};

    if (efficiency != null) queryParams['efficiency'] = efficiency;
    if (growthRate != null) queryParams['growthRate'] = growthRate;
    if (limit != null) queryParams['limit'] = limit.toString();

    final endpoint =
        'carbon-sink/filter-by-efficiency?${_encodeQueryParameters(queryParams)}';
    return get(endpoint);
  }

  // AI永續碳匯助手 - 根據環境條件篩選樹種
  static Future<Map<String, dynamic>> filterByEnvironment({
    String? droughtTolerance,
    String? wetTolerance,
    String? saltTolerance,
    String? pollutionResistance,
    String? soilType,
    int? limit,
  }) async {
    Map<String, String> queryParams = {};

    if (droughtTolerance != null) {
      queryParams['droughtTolerance'] = droughtTolerance;
    }
    if (wetTolerance != null) queryParams['wetTolerance'] = wetTolerance;
    if (saltTolerance != null) queryParams['saltTolerance'] = saltTolerance;
    if (pollutionResistance != null) {
      queryParams['pollutionResistance'] = pollutionResistance;
    }
    if (soilType != null) queryParams['soilType'] = soilType;
    if (limit != null) queryParams['limit'] = limit.toString();

    final endpoint =
        'carbon-sink/filter-by-environment?${_encodeQueryParameters(queryParams)}';
    return get(endpoint);
  }

  // AI永續碳匯助手 - 生成混合造林推薦
  static Future<Map<String, dynamic>> generateMixedForest({
    required String region,
    required double area,
    String? purpose,
    Map<String, String>? environmentalConditions,
    double? carbonGoal,
  }) async {
    final data = {
      'region': region,
      'area': area,
    };

    if (purpose != null) data['purpose'] = purpose;
    if (environmentalConditions != null) {
      data['environmentalConditions'] = environmentalConditions;
    }
    if (carbonGoal != null) data['carbonGoal'] = carbonGoal;

    return post('carbon-sink/mixed-forest', data);
  }

  // 輔助方法：編碼查詢參數
  static String _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }
}

// 擴展 Uri 以支持查詢參數編碼
extension UriExtension on Uri {
  static String encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }
}
