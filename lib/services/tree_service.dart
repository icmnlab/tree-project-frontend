import 'api_service.dart'; // Import ApiService
import 'package:dio/dio.dart'; // Import Dio for file uploads
import 'dart:io'; // Import File for file operations

class TreeService {
  // --- API Methods ---

  Future<Map<String, dynamic>> getAllTrees({
    int? limit,
    int offset = 0,
    String? projectCode,
    String? projectName,
    String? search,
  }) async {
    final q = <String>[];
    if (limit != null) q.add('limit=$limit');
    if (offset > 0) q.add('offset=$offset');
    if (projectCode != null &&
        projectCode.isNotEmpty &&
        projectCode != '全部') {
      q.add('project_code=${Uri.encodeComponent(projectCode)}');
    } else if (projectName != null &&
        projectName.isNotEmpty &&
        projectName != '全部') {
      q.add('project_name=${Uri.encodeComponent(projectName)}');
    }
    if (search != null && search.trim().isNotEmpty) {
      q.add('q=${Uri.encodeComponent(search.trim())}');
    }
    final suffix = q.isEmpty ? '' : '?${q.join('&')}';
    return await ApiService.get('tree_survey$suffix');
  }

  Future<Map<String, dynamic>> getMapMeta({String? city}) async {
    final q = <String>[];
    if (city != null && city.isNotEmpty && city != '全部') {
      q.add('city=${Uri.encodeComponent(city)}');
    }
    final suffix = q.isEmpty ? '/map/meta' : '/map/meta?${q.join('&')}';
    return await ApiService.get('tree_survey$suffix');
  }

  Future<Map<String, dynamic>> getMapTrees({
    String? projectCode,
    String? city,
    double? swLat,
    double? swLng,
    double? neLat,
    double? neLng,
    int? limit,
  }) async {
    final q = <String>[];
    if (limit != null && limit > 0) {
      q.add('limit=$limit');
    }
    if (projectCode != null &&
        projectCode.isNotEmpty &&
        projectCode != '全部') {
      q.add('project_code=${Uri.encodeComponent(projectCode)}');
    }
    if (city != null && city.isNotEmpty && city != '全部') {
      q.add('city=${Uri.encodeComponent(city)}');
    }
    if (swLat != null && swLng != null && neLat != null && neLng != null) {
      q.addAll([
        'sw_lat=$swLat',
        'sw_lng=$swLng',
        'ne_lat=$neLat',
        'ne_lng=$neLng',
      ]);
    }
    final suffix = q.isEmpty ? '' : '?${q.join('&')}';
    return await ApiService.get('tree_survey/map$suffix');
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

  // [T6 cleanup] addTree / updateTree (V1) 已移除，改用 createTreeV2 / updateTreeV2

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
      options: Options(
        headers: ApiService.getAuthHeaders(),
      ),
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
}
