import './api_service.dart';
import './download_service.dart';

class AdminService {
  Future<Map<String, dynamic>> backupDatabase() async {
    // 後端路由為 POST /api/admin/backup（系統管理員）。
    final response = await ApiService.post('admin/backup', {});
    return response;
  }
}

class ExportService {
  static String getExcelExportUrl(List<String> projectCodes) {
    String query = '';
    if (projectCodes.isNotEmpty) {
      query = '?project_codes=${Uri.encodeComponent(projectCodes.join(','))}';
    }
    return '${ApiService.baseUrl}/export/excel$query';
  }

  static String getPdfExportUrl(List<String> projectCodes) {
    String query = '';
    if (projectCodes.isNotEmpty) {
      query = '?project_codes=${Uri.encodeComponent(projectCodes.join(','))}';
    }
    return '${ApiService.baseUrl}/export/pdf$query';
  }

  static Future<DownloadResult> downloadExcel(List<String> projectCodes) async {
    final url = getExcelExportUrl(projectCodes);
    return DownloadService.downloadAndOpen(url, suggestedFilename: 'tree_survey_export.xlsx');
  }

  static Future<DownloadResult> downloadPdf(List<String> projectCodes) async {
    final url = getPdfExportUrl(projectCodes);
    return DownloadService.downloadAndOpen(url, suggestedFilename: 'tree_survey_export.pdf');
  }
}
