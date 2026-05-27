import 'package:flutter/foundation.dart';

import '../project_service.dart';
import 'project_boundary_service.dart';

/// 專案邊界在全系統中的語意（單一真相來源）
///
/// | 狀態 | 自動匹配 GPS | 手動提交 | 地圖顯示 | BLE 指派 |
/// |------|-------------|---------|---------|---------|
/// | 無邊界 | 不匹配／手選 | 允許（手動模式） | 不畫 polygon | 全 outside |
/// | 有邊界 | 點在多邊形內才匹配 | 點在內才通過 | 畫 polygon | 依座標匹配 |
/// | 剛儲存邊界 | 需刷新快取 | 需刷新快取 | 需 forceRefresh | 已 forceRefresh |
enum BoundaryEnforcement {
  /// 無邊界時不阻擋（調查初期）
  manualModeAllowNoBoundary,

  /// 有邊界時必須在內（建議正式調查）
  requireInsideWhenBoundaryExists,

  /// 僅提示，不阻擋（整合表單／待測量）
  warnOnly,
}

/// 邊界決策結果
class BoundaryDecision {
  final bool canProceed;
  final bool hasBoundary;
  final bool isInside;
  final String message;
  final bool shouldRefreshCache;

  const BoundaryDecision({
    required this.canProceed,
    required this.hasBoundary,
    required this.isInside,
    required this.message,
    this.shouldRefreshCache = false,
  });
}

/// 跨頁面邊界協調：快取失效、狀態刷新、canonical 專案名稱
class ProjectBoundaryCoordinator {
  ProjectBoundaryCoordinator._();
  static final ProjectBoundaryCoordinator instance =
      ProjectBoundaryCoordinator._();

  final ProjectBoundaryService _boundaries = ProjectBoundaryService();
  final ProjectService _projects = ProjectService();

  /// 繪製／儲存／刪除邊界後必須呼叫，避免地圖／智慧表單仍用舊快取
  Future<void> afterBoundaryMutation({String? projectName}) async {
    _boundaries.markBoundariesChanged();
    debugPrint(
      '[BoundaryCoordinator] cache invalidated'
      '${projectName != null ? " ($projectName)" : ""}',
    );
  }

  /// 自動 GPS 匹配前：強制與伺服器同步
  Future<List<ProjectBoundary>> beforeAutoMatch() {
    return _boundaries.getAllBoundaries(forceRefresh: true);
  }

  /// 地圖 overlay 載入前
  Future<List<ProjectBoundary>> forMapDisplay({bool forceRefresh = true}) {
    return _boundaries.getAllBoundaries(forceRefresh: forceRefresh);
  }

  /// 手動輸入／V2 提交前驗證
  Future<BoundaryDecision> evaluateSubmit({
    required String projectName,
    required double lat,
    required double lng,
    BoundaryEnforcement enforcement = BoundaryEnforcement.requireInsideWhenBoundaryExists,
  }) async {
    final name = projectName.trim();
    if (name.isEmpty) {
      return const BoundaryDecision(
        canProceed: false,
        hasBoundary: false,
        isInside: false,
        message: '請先選擇專案',
      );
    }

    final validation = await _boundaries.validateCoordinateForProjectFresh(
      projectName: name,
      lat: lat,
      lng: lng,
      preferServer: true,
    );

    if (!validation.hasBoundary) {
      switch (enforcement) {
        case BoundaryEnforcement.manualModeAllowNoBoundary:
          return BoundaryDecision(
            canProceed: true,
            hasBoundary: false,
            isInside: true,
            message: validation.message,
          );
        case BoundaryEnforcement.requireInsideWhenBoundaryExists:
          return BoundaryDecision(
            canProceed: true,
            hasBoundary: false,
            isInside: true,
            message: '該專案尚未設定邊界（手動模式）',
          );
        case BoundaryEnforcement.warnOnly:
          return BoundaryDecision(
            canProceed: true,
            hasBoundary: false,
            isInside: true,
            message: validation.message,
          );
      }
    }

    if (validation.isValid) {
      return BoundaryDecision(
        canProceed: true,
        hasBoundary: true,
        isInside: true,
        message: validation.message,
      );
    }

    switch (enforcement) {
      case BoundaryEnforcement.manualModeAllowNoBoundary:
      case BoundaryEnforcement.warnOnly:
        return BoundaryDecision(
          canProceed: true,
          hasBoundary: true,
          isInside: false,
          message: validation.message,
        );
      case BoundaryEnforcement.requireInsideWhenBoundaryExists:
        return BoundaryDecision(
          canProceed: false,
          hasBoundary: true,
          isInside: false,
          message: validation.message,
        );
    }
  }

  /// 從 projects 表取得 canonical 名稱與 code（避免邊界列與 projects 漂移）
  Future<({String name, String? code, String? area})?> resolveProject(
    String projectNameOrCode,
  ) async {
    try {
      final byName = await _projects.getProjectByName(projectNameOrCode.trim());
      if (byName['success'] == true && byName['data'] != null) {
        final d = byName['data'] as Map<String, dynamic>;
        return (
          name: d['name']?.toString() ?? projectNameOrCode,
          code: d['project_code']?.toString(),
          area: d['area_name']?.toString() ?? d['project_area']?.toString(),
        );
      }
    } catch (_) {}
    return null;
  }

  /// BLE／匹配：補齊 area/code（邊界列可能缺 area）
  Future<Map<String, String?>> enrichProjectFields({
    required String? projectName,
    String? projectCode,
    String? projectArea,
  }) async {
    if (projectName == null || projectName.isEmpty) {
      return {
        'name': projectName,
        'code': projectCode,
        'area': projectArea,
      };
    }
    final resolved = await resolveProject(projectName);
    if (resolved == null) {
      return {
        'name': projectName,
        'code': projectCode,
        'area': projectArea,
      };
    }
    return {
      'name': resolved.name,
      'code': projectCode ?? resolved.code,
      'area': projectArea ?? resolved.area,
    };
  }
}
