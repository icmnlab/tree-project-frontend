import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/tree_species.dart';
import 'api_service.dart'; // Import ApiService
import 'package:dio/dio.dart'; // Import Dio for file uploads
import 'dart:io'; // Import File for file operations

class TreeService {
  List<TreeSpecies> _allSpecies = [];

  // --- API Methods ---

  Future<Map<String, dynamic>> getAllTrees() async {
    return await ApiService.get('tree_survey');
  }

  Future<Map<String, dynamic>> getTreesByProjectName(String projectName) async {
    final String encodedName = Uri.encodeComponent(projectName);
    return await ApiService.get('tree_survey/by_project/$encodedName');
  }

  Future<Map<String, dynamic>> getTreesByProjectCode(String projectCode) async {
    final String encodedCode = Uri.encodeComponent(projectCode);
    final response =
        await ApiService.get('tree_survey/by_project/$encodedCode');
    return response;
  }

  Future<Map<String, dynamic>> getTreesByArea(String areaName) async {
    final String encodedName = Uri.encodeComponent(areaName);
    return await ApiService.get('tree_survey/by_area/$encodedName');
  }

  Future<Map<String, dynamic>> addTree(Map<String, dynamic> treeData) async {
    return await ApiService.post('tree_survey', treeData);
  }

  Future<Map<String, dynamic>> updateTree(
      String id, Map<String, dynamic> treeData) async {
    return await ApiService.put('tree_survey/$id', treeData);
  }

  Future<Map<String, dynamic>> deleteTree(String id) async {
    return await ApiService.delete('tree_survey/$id');
  }

  // [V2 NEW] Get a single tree by its ID
  Future<Map<String, dynamic>> getTreeById(String id) async {
    return await ApiService.get('tree_survey/by_id/$id');
  }

  Future<Map<String, dynamic>> deletePlaceholderTree(String id) async {
    return await ApiService.delete('tree_survey/placeholder/$id');
  }

  Future<Map<String, dynamic>> getNextSystemTreeNumber() async {
    return await ApiService.get('tree_survey/next_system_number');
  }

  Future<Map<String, dynamic>> getNextProjectTreeNumber(
      String projectCode) async {
    return await ApiService.get('tree_survey/next_project_number/$projectCode');
  }

  Future<List<Map<String, dynamic>>> getCommonSpecies(
      String projectCode) async {
    final response =
        await ApiService.get('tree_survey/common_species/$projectCode');
    if (response['success'] == true && response['data'] is List) {
      return List<Map<String, dynamic>>.from(response['data']);
    }
    throw Exception('Failed to load common species for project $projectCode');
  }

  String getTemplateDownloadUrl() {
    return '${ApiService.baseUrl}/tree_survey/template';
  }

  Future<Map<String, dynamic>> importTrees(
      File file, Function(double) onProgress) async {
    String fileName = file.path.split('/').last;
    FormData formData = FormData.fromMap({
      "file": await MultipartFile.fromFile(file.path, filename: fileName),
    });

    Dio dio = Dio();
    final response = await dio.post(
      '${ApiService.baseUrl}/tree_survey/import',
      data: formData,
      onSendProgress: (int sent, int total) {
        onProgress(sent / total);
      },
    );
    return response.data;
  }

  Future<Map<String, dynamic>> batchImportTreesV2(
      Map<String, dynamic> payload) async {
    return await ApiService.post('tree_survey/batch_import', payload);
  }

  Future<Map<String, dynamic>> createTreeV2(
      Map<String, dynamic> treeData) async {
    return await ApiService.post('tree_survey/create_v2', treeData);
  }

  // [V2 NEW] Update a tree via the V2 endpoint
  Future<Map<String, dynamic>> updateTreeV2(
      String id, Map<String, dynamic> treeData) async {
    return await ApiService.put('tree_survey/update_v2/$id', treeData);
  }

  Future<void> cleanupTemporaryData() async {
    // This method is intended to clean up temporary or incomplete data on the backend.
    // The endpoint 'project_areas/cleanup' is used here based on the original http call.
    // Consider moving this to a more appropriate service if the backend logic evolves.
    await ApiService.post('project_areas/cleanup', {});
  }

  // --- Local Asset Methods ---

  // 載入所有樹種數據
  Future<void> loadTreeSpecies() async {
    if (_allSpecies.isNotEmpty) return;

    try {
      final jsonString =
          await rootBundle.loadString('assets/data/tree_species.json');
      final List<dynamic> jsonList = json.decode(jsonString);
      _allSpecies = jsonList.map((json) => TreeSpecies.fromJson(json)).toList();
    } catch (e) {
      print('載入樹種數據時出錯: $e');
      // 在實際應用中，可能需要更好的錯誤處理
      _allSpecies = [];
    }
  }

  // 功能1：精確計算特定樹種的碳吸收量
  double calculateSpeciesCarbon(
      String speciesId, int ageInYears, int quantity) {
    final species = _allSpecies.firstWhere(
      (s) => s.id == speciesId,
      orElse: () => throw Exception('找不到樹種ID: $speciesId'),
    );

    return species.calculateCarbonAbsorption(ageInYears) * quantity;
  }

  // 功能2：根據樹木數量和年齡計算總碳吸收量
  Map<String, dynamic> calculateTotalCarbon(
      Map<String, Map<String, dynamic>> treesData) {
    double totalCarbon = 0;
    Map<String, double> speciesContribution = {};

    treesData.forEach((speciesId, data) {
      final int quantity = data['quantity'];
      final int ageInYears = data['age'];

      final carbon = calculateSpeciesCarbon(speciesId, ageInYears, quantity);
      totalCarbon += carbon;

      final species = _allSpecies.firstWhere((s) => s.id == speciesId);
      speciesContribution[species.name] = carbon;
    });

    return {
      'totalCarbon': totalCarbon,
      'speciesContribution': speciesContribution,
    };
  }

  // 功能3：根據地區推薦適合樹種
  List<TreeSpecies> recommendByRegion(String region) {
    return _allSpecies
        .where((species) => species.suitableRegions.contains(region))
        .toList();
  }

  // 功能4：依碳吸收效率篩選樹種
  List<TreeSpecies> filterByEfficiency(int age, {int limit = 10}) {
    // 根據特定年齡的碳吸收效率排序
    final sorted = List<TreeSpecies>.from(_allSpecies);
    sorted.sort((a, b) => b
        .calculateCarbonAbsorption(age)
        .compareTo(a.calculateCarbonAbsorption(age)));

    // 返回碳吸收效率最高的前limit個樹種
    return sorted.take(limit).toList();
  }

  // 功能5：根據環境條件篩選樹種
  List<TreeSpecies> filterByEnvironment(Map<String, dynamic> conditions) {
    return _allSpecies.where((species) {
      // 檢查每個環境條件
      if (conditions.containsKey('soilType') &&
          conditions['soilType'] != null &&
          species.soilType != conditions['soilType']) {
        return false;
      }

      if (conditions.containsKey('sunExposure') &&
          conditions['sunExposure'] != null &&
          species.sunExposure != conditions['sunExposure']) {
        return false;
      }

      if (conditions.containsKey('minTemperature') &&
          conditions['minTemperature'] != null &&
          species.minTemperature < conditions['minTemperature']) {
        return false;
      }

      if (conditions.containsKey('maxTemperature') &&
          conditions['maxTemperature'] != null &&
          species.maxTemperature > conditions['maxTemperature']) {
        return false;
      }

      return true;
    }).toList();
  }

  // 功能6：生成混合造林推薦
  Map<String, dynamic> generateMixedForest(String region,
      Map<String, dynamic> environmentConditions, int totalArea) {
    // 首先，獲取符合地區和環境條件的樹種
    List<TreeSpecies> suitableSpecies = recommendByRegion(region);
    suitableSpecies = filterByEnvironment(environmentConditions);

    if (suitableSpecies.isEmpty) {
      return {
        'success': false,
        'message': '沒有找到符合條件的樹種',
        'recommendation': {},
      };
    }

    // 根據碳吸收效率進行排序（使用樹齡30年的數據）
    suitableSpecies.sort((a, b) => b
        .calculateCarbonAbsorption(30)
        .compareTo(a.calculateCarbonAbsorption(30)));

    // 生成混合森林推薦
    Map<String, dynamic> recommendation = {};
    double remainingArea = totalArea.toDouble();

    // 選擇效率前3的樹種，按比例分配面積
    final topSpecies = suitableSpecies.take(3).toList();

    // 計算總效率，用於分配比例
    double totalEfficiency = topSpecies.fold(
        0, (sum, species) => sum + species.calculateCarbonAbsorption(30));

    for (int i = 0; i < topSpecies.length; i++) {
      final species = topSpecies[i];
      double proportion =
          species.calculateCarbonAbsorption(30) / totalEfficiency;

      // 最後一個樹種分配剩餘的所有面積
      double area = (i == topSpecies.length - 1)
          ? remainingArea
          : (totalArea * proportion).roundToDouble();

      if (area > remainingArea) area = remainingArea;
      remainingArea -= area;

      recommendation[species.name] = {
        'id': species.id,
        'area': area,
        'proportion': proportion,
        'estimated_carbon_30yr': species.calculateCarbonAbsorption(30) * area,
      };

      if (remainingArea <= 0) break;
    }

    // 計算總碳吸收量（30年）
    double totalCarbon30yr = 0;
    recommendation.forEach((_, data) {
      totalCarbon30yr += data['estimated_carbon_30yr'];
    });

    return {
      'success': true,
      'totalArea': totalArea,
      'totalCarbon30yr': totalCarbon30yr,
      'recommendation': recommendation,
    };
  }

  // 獲取所有樹種
  List<TreeSpecies> getAllSpecies() {
    return List.unmodifiable(_allSpecies);
  }

  // 根據ID獲取樹種
  TreeSpecies? getSpeciesById(String id) {
    try {
      return _allSpecies.firstWhere((species) => species.id == id);
    } catch (e) {
      return null;
    }
  }
}
