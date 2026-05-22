import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'api_service.dart';

class DownloadService {
  /// Agent / Chat 匯出連結（/api/download/…）應在 App 內下載，勿用外部瀏覽器（Chrome 無法信任 .ts.net 自簽憑證）
  static bool isAppDownloadUrl(String? href) {
    if (href == null || href.isEmpty) return false;
    final u = href.toLowerCase();
    return u.contains('/api/download/') || u.contains('/download/');
  }

  /// 將相對或完整 URL 解析為目前 App 設定的 API 主機
  static String resolveDownloadUrl(String href) {
    final trimmed = href.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final parsed = Uri.parse(trimmed);
      if (isAppDownloadUrl(parsed.path)) {
        final api = Uri.parse(ApiService.baseUrl);
        return parsed.replace(
          scheme: api.scheme,
          host: api.host,
          port: api.port,
        ).toString();
      }
      return trimmed;
    }
    if (trimmed.startsWith('/api/download/')) {
      final api = Uri.parse(ApiService.baseUrl);
      return '${api.scheme}://${api.host}${api.hasPort ? ':${api.port}' : ''}$trimmed';
    }
    if (trimmed.startsWith('/download/')) {
      final api = Uri.parse(ApiService.baseUrl);
      return '${api.scheme}://${api.host}${api.hasPort ? ':${api.port}' : ''}/api$trimmed';
    }
    return trimmed;
  }

  static Future<DownloadResult> downloadAgentExport(String href) async {
    final url = resolveDownloadUrl(href);
    final uri = Uri.parse(url);
    final name = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null;
    return downloadAndOpen(url, suggestedFilename: name);
  }

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
      // 使用更簡單的正則表達式避免 Dart 解析問題
      final filenamePattern = RegExp(r'filename[^;=\n]*=([^;\n]*)');
      final match = filenamePattern.firstMatch(contentDisposition);
      if (match != null && match.groupCount >= 1) {
        var filename = match.group(1) ?? '';
        // 移除前後的引號
        filename = filename.trim();
        if (filename.startsWith('"') && filename.endsWith('"')) {
          filename = filename.substring(1, filename.length - 1);
        } else if (filename.startsWith("'") && filename.endsWith("'")) {
          filename = filename.substring(1, filename.length - 1);
        }
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
