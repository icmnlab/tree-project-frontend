import './api_service.dart';
import 'package:url_launcher/url_launcher.dart';

class AdminService {
  Future<Map<String, dynamic>> backupDatabase() async {
    // This action still triggers a direct request via ApiService
    // to handle the backup process on the backend.
    final response = await ApiService.post('backup', {});
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

  static Future<void> launchExportUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw 'Could not launch $url';
    }
  }
}
