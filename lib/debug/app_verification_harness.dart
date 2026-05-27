import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/carbon_calculation_service.dart';
import '../services/handbook_carbon_service.dart';
import '../services/network_service.dart';
import '../services/v3/project_boundary_coordinator.dart';
import '../services/v3/project_boundary_service.dart';
import '../utils/carbon_display.dart';

/// 啟動時自動偵錯驗證（對照 VERIFICATION_CHECKLIST.md）
///
/// - Debug 建置：預設執行
/// - Release 建置：`flutter run --release --dart-define=RUN_VERIFICATION_HARNESS=true`
class AppVerificationHarness {
  static int _pass = 0;
  static int _fail = 0;
  static int _skip = 0;

  static bool get enabled {
    const force = bool.fromEnvironment('RUN_VERIFICATION_HARNESS');
    if (force) return true;
    const disable = bool.fromEnvironment('SKIP_VERIFICATION_HARNESS');
    if (disable) return false;
    return kDebugMode;
  }

  static Future<void> runIfEnabled() async {
    if (!enabled) return;
    _pass = 0;
    _fail = 0;
    _skip = 0;
    final started = DateTime.now();
    _banner('開始驗證偵錯報告');
    _line('INFO', 'BUILD', kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'));
    _line('INFO', 'HARNESS', '對照 docs/VERIFICATION_CHECKLIST.md；手動步驟（拍照/BLE/409 衝突）仍需實機勾選');

    await _section0Environment();
    await _sectionCarbon();
    await _sectionBoundary();
    await _sectionAuthApi();

    final ms = DateTime.now().difference(started).inMilliseconds;
    _banner('驗證摘要 PASS=$_pass FAIL=$_fail SKIP=$_skip (${ms}ms)');
    if (_fail > 0) {
      _line('FAIL', 'SUMMARY', '有 $_fail 項未通過 — 請依 [VERIFY][FAIL] 代碼排查');
    } else {
      _line('PASS', 'SUMMARY', '自動檢查全部通過（不含需人工操作的 UI 流程）');
    }
  }

  static void _banner(String title) {
    final bar = '=' * 60;
    _logRaw('\n$bar\n[VERIFY] $title\n$bar');
  }

  static void _section(String name) {
    _logRaw('\n--- [VERIFY] $name ---');
  }

  static void _passCheck(String code, String detail) {
    _pass++;
    _line('PASS', code, detail);
  }

  static void _failCheck(String code, String detail) {
    _fail++;
    _line('FAIL', code, detail);
  }

  static void _skipCheck(String code, String detail) {
    _skip++;
    _line('SKIP', code, detail);
  }

  static void _line(String level, String code, String message) {
    _logRaw('[VERIFY][$level][$code] $message');
  }

  static void _logRaw(String line) {
    // ignore: avoid_print — 刻意輸出到 flutter run / release terminal
    print(line);
    debugPrint(line);
  }

  static Future<void> _section0Environment() async {
    _section('§0 環境');
    final base = AppConfig().baseUrl;
    if (base.isNotEmpty) {
      _passCheck('ENV-001', 'baseUrl=$base');
    } else {
      _failCheck('ENV-001', 'baseUrl 為空');
    }

    if (NetworkService().isConnected) {
      _passCheck('ENV-002', '裝置網路：已連線');
    } else {
      _failCheck('ENV-002', '裝置網路：離線（後端 API 檢查可能失敗）');
    }

    try {
      final root = base.replaceFirst(RegExp(r'/api/?$'), '');
      final uri = Uri.parse('$root/health');
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        _passCheck('ENV-003', 'GET $uri → ${res.statusCode}');
      } else {
        _failCheck('ENV-003', 'GET $uri → ${res.statusCode} ${res.body.substring(0, res.body.length.clamp(0, 120))}');
      }
    } catch (e) {
      _failCheck('ENV-003', '後端 /health 無法連線: $e');
    }

    final ml = AppConfig().mlServiceUrl;
    if (ml.isEmpty) {
      _skipCheck('ENV-004', 'ML Service URL 未設定（DBH 雲端推論可能不可用）');
    } else {
      _passCheck('ENV-004', 'mlServiceUrl=$ml');
    }
  }

  static Future<void> _sectionCarbon() async {
    _section('碳匯（tree_survey 欄位 + 手冊公式）');
    _line('INFO', 'CARB-FIELDS',
        '${CarbonDisplay.fieldStorage}（存量 kg CO₂e）| ${CarbonDisplay.fieldAnnual}（年流量 kg CO₂e/年，僅讀 DB）');

    await HandbookCarbonService.preload();
    final sample = CarbonCalculationService.calculateCarbonStorage(
      '台灣肖楠',
      12.0,
      35.0,
    );
    if (sample > 0) {
      _passCheck('CARB-001',
          '手冊第六章試算 台灣肖楠 H=12m DBH=35cm → ${sample.toStringAsFixed(2)} kg CO₂e');
    } else {
      _failCheck('CARB-001', '手冊試算結果為 0（檢查 assets/coa/coa_volume_equations.json）');
    }

    final annual = CarbonCalculationService.calculateAnnualCarbonSequestration(
      '台灣肖楠',
      12,
      35,
      30,
    );
    if (annual == 0) {
      _passCheck('CARB-002', '年固碳量客戶端不重算（deprecated 回傳 0）');
    } else {
      _failCheck('CARB-002', '年固碳量不應在客戶端重算，卻得到 $annual');
    }

    for (final ref in CarbonDisplay.literatureRefs) {
      _line('INFO', 'CARB-REF', ref);
    }
  }

  static Future<void> _sectionBoundary() async {
    _section('§2 專案邊界（快取 / 協調器）');
    final svc = ProjectBoundaryService();
    svc.markBoundariesChanged();
    if (!svc.hasCache) {
      _passCheck('BND-001', 'markBoundariesChanged 後快取已清空');
    } else {
      _failCheck('BND-001', 'markBoundariesChanged 後快取仍存在 (${svc.cachedBoundaryCount} 筆)');
    }

    await ProjectBoundaryCoordinator.instance.afterBoundaryMutation(
      projectName: '__harness__',
    );
    _passCheck('BND-002', 'ProjectBoundaryCoordinator.afterBoundaryMutation 可呼叫');

    _line('INFO', 'BND-MANUAL', 'B1–B7、N1–N6 需實機：繪製邊界、登出換帳、智慧匹配 — 見 VERIFICATION_CHECKLIST');
  }

  static Future<void> _sectionAuthApi() async {
    _section('API（需登入項目）');
    final token = ApiService.getJwtToken();
    final loggedIn = await AuthService.isLoggedIn();

    if (token == null || !loggedIn) {
      _skipCheck('API-001', '未登入 — 略過 project-boundaries / tree_survey 探測');
      _line('INFO', 'API-HINT', '登入後重新啟動 App 可重跑邊界與權限檢查');
      return;
    }

    _passCheck('API-001', 'JWT 已載入（長度 ${token.length}）');

    try {
      final res = await ApiService.get('project-boundaries');
      if (res['success'] == true) {
        final data = res['data'];
        final n = data is List ? data.length : '?';
        _passCheck('BND-003', 'GET project-boundaries → 可讀（約 $n 筆）');
      } else {
        final body = jsonEncode(res);
        _failCheck(
          'BND-003',
          'GET project-boundaries: ${body.length > 200 ? body.substring(0, 200) : body}',
        );
      }
    } catch (e) {
      _failCheck('BND-003', 'GET project-boundaries 例外: $e');
    }

    _line('INFO', 'LOCK-MANUAL', 'L1–L5 409 樂觀鎖需兩裝置或同任務實測 — 無法全自動');
    _line('INFO', 'FIELD-MANUAL', 'F1–F3 現場測量 / 拍照模式需 BLE 與相機實測');
  }
}
