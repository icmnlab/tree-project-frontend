import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'api_service.dart';

class DownloadService {
  static const _timeout = Duration(seconds: 120);

  /// Agent / Chat 匯出連結應在 App 內下載（勿開 Chrome，.ts.net 自簽憑證會失敗）
  static bool isAppDownloadUrl(String? href) {
    if (href == null || href.isEmpty) return false;
    final u = href.toLowerCase();
    return u.contains('/download/') ||
        u.endsWith('.xlsx') ||
        u.endsWith('.pdf');
  }

  /// 從各種 Agent 回傳格式抽出檔名
  static String? extractDownloadFilename(String href) {
    final trimmed = href.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final uri = Uri.parse(trimmed);
      final segs = uri.pathSegments;
      if (segs.isNotEmpty && segs.last.contains('.')) {
        return Uri.decodeComponent(segs.last);
      }
    }

    const markers = ['/api/download/', '/download/'];
    for (final m in markers) {
      final idx = trimmed.indexOf(m);
      if (idx >= 0) {
        var tail = trimmed.substring(idx + m.length).split('?').first.split('#').first;
        if (tail.isNotEmpty) return Uri.decodeComponent(tail);
      }
    }

    if (!trimmed.contains('/') &&
        (trimmed.endsWith('.xlsx') || trimmed.endsWith('.pdf'))) {
      return Uri.decodeComponent(trimmed);
    }
    return null;
  }

  /// 一律用 App 的 ApiService.baseUrl 組下載網址
  static String resolveDownloadUrl(String href) {
    final file = extractDownloadFilename(href);
    if (file == null || file.isEmpty) {
      return href.trim();
    }
    final base = ApiService.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final encoded = Uri.encodeComponent(file);
    return '$base/download/$encoded';
  }

  static Future<DownloadResult> downloadAgentExport(String href) async {
    return downloadAndOpen(resolveDownloadUrl(href), suggestedFilename: extractDownloadFilename(href));
  }

  static Future<DownloadResult> downloadAndOpen(
    String url, {
    String? suggestedFilename,
    bool openAfterDownload = true,
  }) async {
    try {
      final uri = Uri.parse(url);
      final headers = ApiService.getAuthHeaders();

      final response = await http.get(uri, headers: headers).timeout(_timeout);

      if (response.statusCode == 401) {
        return DownloadResult(
          success: false,
          error: '請重新登入後再下載',
        );
      }

      if (response.statusCode != 200) {
        String detail = 'HTTP ${response.statusCode}';
        try {
          final body = json.decode(response.body);
          if (body is Map && body['message'] != null) {
            detail = body['message'].toString();
          }
        } catch (_) {
          if (response.body.isNotEmpty && response.body.length < 200) {
            detail = response.body;
          }
        }
        return DownloadResult(success: false, error: '下載失敗: $detail');
      }

      final contentType = response.headers['content-type'] ?? '';
      if (contentType.contains('application/json')) {
        try {
          final body = json.decode(response.body);
          if (body is Map && body['message'] != null) {
            return DownloadResult(
              success: false,
              error: body['message'].toString(),
            );
          }
        } catch (_) {}
        return DownloadResult(success: false, error: '下載失敗: 伺服器回傳非檔案內容');
      }

      final filename = suggestedFilename ?? _extractFilename(response, uri);
      final directory = await getApplicationDocumentsDirectory();
      final downloadsDir = Directory('${directory.path}/downloads');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      final safeName = filename.split(RegExp(r'[/\\]')).last;
      final filePath = '${downloadsDir.path}/$safeName';
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      debugPrint('[DownloadService] File saved to: $filePath (${response.bodyBytes.length} bytes)');

      if (openAfterDownload) {
        final result = await OpenFilex.open(filePath);
        if (result.type != ResultType.done) {
          return DownloadResult(
            success: true,
            filePath: filePath,
            warning: '檔案已下載至 App，但無法自動開啟: ${result.message}',
          );
        }
      }

      return DownloadResult(success: true, filePath: filePath);
    } on HandshakeException catch (e) {
      return DownloadResult(
        success: false,
        error: 'TLS 連線失敗，請確認已使用 App 內下載而非瀏覽器: $e',
      );
    } on SocketException catch (e) {
      return DownloadResult(
        success: false,
        error: '無法連線伺服器: $e',
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
      final filenamePattern = RegExp(r'filename[^;=\n]*=([^;\n]*)');
      final match = filenamePattern.firstMatch(contentDisposition);
      if (match != null && match.groupCount >= 1) {
        var filename = match.group(1) ?? '';
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
        return Uri.decodeComponent(lastSegment);
      }
    }

    final contentType = response.headers['content-type'] ?? '';
    String extension = '.bin';
    if (contentType.contains('excel') || contentType.contains('spreadsheet')) {
      extension = '.xlsx';
    } else if (contentType.contains('pdf')) {
      extension = '.pdf';
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
