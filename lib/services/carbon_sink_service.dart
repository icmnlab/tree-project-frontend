import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/tree_species.dart';
import './api_service.dart';

class CarbonSinkService {
  List<TreeSpecies> _treeSpecies = [];
  bool _isInitialized = false;

  // 單例模式
  static final CarbonSinkService _instance = CarbonSinkService._internal();

  factory CarbonSinkService() {
    return _instance;
  }

  CarbonSinkService._internal();

  bool get isInitialized => _isInitialized;

  // 初始化加載樹種數據 - 改進錯誤處理
  Future<void> initialize() async {
    if (_isInitialized && _treeSpecies.isNotEmpty) {
      print('樹種資料已加載，不需重新初始化');
      return;
    }

    try {
      // 嘗試從API獲取數據
      await _loadFromApi();

      // 如果API獲取失敗，嘗試從本地資源文件加載
      if (_treeSpecies.isEmpty) {
        await _loadFromAssets();
      }

      _isInitialized = true;
      print('成功載入 ${_treeSpecies.length} 種樹木資料');
    } catch (e) {
      print('載入樹種資料時出錯: $e');
      // 發生錯誤時創建空列表，避免空引用
      _treeSpecies = [];
      _isInitialized = false;
      rethrow;
    }
  }

  // 從API加載數據
  Future<void> _loadFromApi() async {
    try {
      final response = await ApiService.getTreeSpecies();

      if (response['success'] == true && response['data'] != null) {
        List<dynamic> jsonData = response['data'];
        _treeSpecies =
            jsonData.map((json) => TreeSpecies.fromJson(json)).toList();
        print('從API加載了 ${_treeSpecies.length} 種樹木資料');
      } else {
        print('API返回錯誤或無數據: ${response['message']}');
      }
    } catch (e) {
      print('從API加載樹種資料時出錯: $e');
      // 不拋出異常，允許嘗試下一個數據源
    }
  }

  // 從本地資源文件加載數據
  Future<void> _loadFromAssets() async {
    try {
      String jsonString =
          await rootBundle.loadString('assets/data/tree_species.json');

      // 嘗試解析JSON
      List<dynamic> jsonData = jsonDecode(jsonString);
      _treeSpecies =
          jsonData.map((json) => TreeSpecies.fromJson(json)).toList();

      print('從本地資源加載了 ${_treeSpecies.length} 種樹木資料');
    } catch (e) {
      print('從本地資源加載樹種資料時出錯: $e');
      _treeSpecies = [];
      rethrow;
    }
  }

  // 取得所有樹種
  List<TreeSpecies> getAllSpecies() {
    if (_treeSpecies.isEmpty) {
      print('警告: 樹種資料尚未載入或為空');
    }
    return _treeSpecies;
  }

  // 精確計算特定樹種的碳吸收量
  double calculateSpeciesCarbon(String speciesId, int age) {
    try {
      TreeSpecies species = _treeSpecies.firstWhere(
        (s) => s.id == speciesId,
        orElse: () => throw Exception('樹種不存在: $speciesId'),
      );

      return species.calculateCarbonAbsorption(age);
    } catch (e) {
      print('計算樹種碳吸收量錯誤: $e');
      return 0.0; // 返回默認值
    }
  }

  // 計算總碳吸收量
  double calculateTotalCarbon(String speciesId, int count, int age) {
    try {
      double carbonPerTree = calculateSpeciesCarbon(speciesId, age);
      return carbonPerTree * count;
    } catch (e) {
      print('計算總碳吸收量錯誤: $e');
      return 0.0;
    }
  }

  // 根據地區推薦適合樹種
  List<TreeSpecies> recommendByRegion(String region) {
    try {
      return _treeSpecies
          .where((species) => species.suitableRegions.contains(region))
          .toList();
    } catch (e) {
      print('根據地區推薦樹種錯誤: $e');
      return [];
    }
  }

  // 依碳吸收效率篩選樹種
  List<TreeSpecies> filterByEfficiency(double minEfficiency) {
    try {
      return _treeSpecies
          .where((species) => species.carbonEfficiency >= minEfficiency)
          .toList();
    } catch (e) {
      print('依碳吸收效率篩選樹種錯誤: $e');
      return [];
    }
  }

  // 根據環境條件篩選樹種
  List<TreeSpecies> filterByEnvironment({
    String? soilType,
    String? sunExposure,
    double? minTemperature,
    double? maxTemperature,
  }) {
    try {
      return _treeSpecies.where((species) {
        bool matches = true;

        if (soilType != null) {
          matches = matches && species.soilType == soilType;
        }

        if (sunExposure != null) {
          matches = matches && species.sunExposure == sunExposure;
        }

        if (minTemperature != null) {
          matches = matches && species.minTemperature >= minTemperature;
        }

        if (maxTemperature != null) {
          matches = matches && species.maxTemperature <= maxTemperature;
        }

        return matches;
      }).toList();
    } catch (e) {
      print('根據環境條件篩選樹種錯誤: $e');
      return [];
    }
  }

  // 生成混合造林推薦
  List<TreeSpecies> generateMixedForest({
    required String region,
    required int desiredSpeciesCount,
    double minEfficiency = 0.0,
    String? soilType,
    String? sunExposure,
  }) {
    try {
      // 先篩選符合條件的樹種
      List<TreeSpecies> candidates = recommendByRegion(region);

      if (minEfficiency > 0) {
        candidates = candidates
            .where((species) => species.carbonEfficiency >= minEfficiency)
            .toList();
      }

      if (soilType != null) {
        candidates = candidates
            .where((species) => species.soilType == soilType)
            .toList();
      }

      if (sunExposure != null) {
        candidates = candidates
            .where((species) => species.sunExposure == sunExposure)
            .toList();
      }

      // 按碳吸收效率排序
      candidates
          .sort((a, b) => b.carbonEfficiency.compareTo(a.carbonEfficiency));

      // 返回指定數量的樹種，如果候選數量不足，則返回所有候選
      int resultCount = candidates.length < desiredSpeciesCount
          ? candidates.length
          : desiredSpeciesCount;

      return candidates.isNotEmpty ? candidates.sublist(0, resultCount) : [];
    } catch (e) {
      print('生成混合造林推薦錯誤: $e');
      return [];
    }
  }

  // 強制重新加載數據
  Future<void> reloadData() async {
    _isInitialized = false;
    await initialize();
  }
}
