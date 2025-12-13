import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'api_service.dart';

class DownloadService {
  static Future<DownloadResult> downloadAndOpen(
    String url, {
    String? suggestedFilename,
    bool openAfterDownload = true,
  }) async {
    try {
      final uri = Uri.parse(url);
      
      final response = await http.get(
        uri,
        headers: ApiService.getAuthHeaders(),
      );

      if (response.statusCode != 200) {
        return DownloadResult(
          success: false,
          error: '下載失敗: HTTP ${response.statusCode}',
        );
      }

      final filename = suggestedFilename ?? _extractFilename(response, uri);
      final directory = await getApplicationDocumentsDirectory();
      final downloadsDir = Directory('${directory.path}/downloads');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      final filePath = '${downloadsDir.path}/$filename';
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      debugPrint('[DownloadService] File saved to: $filePath');

      if (openAfterDownload) {
        final result = await OpenFilex.open(filePath);
        if (result.type != ResultType.done) {
          return DownloadResult(
            success: true,
            filePath: filePath,
            warning: '檔案已下載但無法開啟: ${result.message}',
          );
        }
      }

      return DownloadResult(
        success: true,
        filePath: filePath,
      );
    } catch (e) {
      debugPrint('[DownloadService] Download error: $e');
      return DownloadResult(
        success: false,
        error: '下載時發生錯誤: $e',
      );
    }
  }

  static String _extractFilename(http.Response response, Uri uri) {
    final contentDisposition = response.headers['content-disposition'];
    if (contentDisposition != null) {
      final filenameMatch = RegExp(r'filename[^;=\n]*=((["\']).*?\2|[^;\n]*)').firstMatch(contentDisposition);
      if (filenameMatch != null) {
        var filename = filenameMatch.group(1) ?? '';
        filename = filename.replaceAll(RegExp(r'^["\']|["\']$'), '');
        if (filename.isNotEmpty) {
          return Uri.decodeComponent(filename);
        }
      }
    }

    final pathSegments = uri.pathSegments;
    if (pathSegments.isNotEmpty) {
      final lastSegment = pathSegments.last;
      if (lastSegment.contains('.')) {
        return lastSegment;
      }
    }

    final contentType = response.headers['content-type'] ?? '';
    String extension = '.bin';
    if (contentType.contains('excel') || contentType.contains('spreadsheet')) {
      extension = '.xlsx';
    } else if (contentType.contains('pdf')) {
      extension = '.pdf';
    } else if (contentType.contains('json')) {
      extension = '.json';
    } else if (contentType.contains('csv')) {
      extension = '.csv';
    }

    return 'download_${DateTime.now().millisecondsSinceEpoch}$extension';
  }
}

class DownloadResult {
  final bool success;
  final String? filePath;
  final String? error;
  final String? warning;

  DownloadResult({
    required this.success,
    this.filePath,
    this.error,
    this.warning,
  });
}
