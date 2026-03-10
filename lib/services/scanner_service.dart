import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/app_config.dart';

/// 即時掃描服務
///
/// 連接 WebSocket，串流相機影像至後端，
/// 接收即時 mask 與 DBH 回應。
class ScannerService {
  WebSocketChannel? _channel;
  StreamController<ScannerResponse>? _responseController;
  bool _isStreaming = false;

  /// 目標解析度（縮小以減少頻寬與延遲）
  static const int targetWidth = 640;
  static const int targetHeight = 480;

  /// 取得 scan WebSocket URL
  ///
  /// - 預設: ws://localhost:8100/ws/scan
  /// - 使用 ngrok 自架時: 從 mlServiceUrl 衍生 wss 位址
  String get _wsUrl {
    final config = AppConfig();
    String url = 'ws://localhost:8100/ws/scan';
    
    if (config.useSelfHostedMl && config.mlServiceUrl.isNotEmpty) {
      // https://xxx.ngrok-free.app/api/v1 -> wss://xxx.ngrok-free.app/ws/scan
      try {
        final uri = Uri.parse(config.mlServiceUrl);
        final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
        url = '$scheme://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}/ws/scan';
      } catch (e) {
        debugPrint('[ScannerService] ngrok URL parse error: $e');
      }
    }
    
    // 從 Render 取得的 API Key 動態附加
    final apiKey = config.mlApiKey;
    if (apiKey != null && apiKey.isNotEmpty) {
      final separator = url.contains('?') ? '&' : '?';
      url = '$url${separator}api_key=$apiKey';
    }
    
    return url;
  }

  /// 是否已連線
  bool get isConnected => _channel != null;

  /// 是否正在串流
  bool get isStreaming => _isStreaming;

  /// 回應串流（mask + dbh）
  Stream<ScannerResponse>? get responseStream => _responseController?.stream;

  /// 連線至 scan WebSocket
  Future<void> connect() async {
    if (_channel != null) return;

    final url = _wsUrl;
    debugPrint('[ScannerService] Connecting to $url');

    try {
      _responseController = StreamController<ScannerResponse>.broadcast();
      _channel = WebSocketChannel.connect(Uri.parse(url));

      // 監聯訊息
      _channel!.stream.listen(
        _onMessage,
        onError: (e) {
          debugPrint('[ScannerService] WS error: $e');
          _responseController?.addError(e);
        },
        onDone: () {
          debugPrint('[ScannerService] WS closed');
          _dispose();
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[ScannerService] Connect failed: $e');
      _dispose();
      rethrow;
    }
  }

  void _onMessage(dynamic data) {
    if (data is! String) return;
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final response = ScannerResponse.fromJson(json);
      _responseController?.add(response);
    } catch (e) {
      debugPrint('[ScannerService] Parse error: $e');
    }
  }

  /// 傳送一幀影像（base64 JPEG）
  ///
  /// [frameBase64] 已縮放至約 640x480 的 JPEG base64
  void sendFrame(String frameBase64) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode({'image': frameBase64}));
    } catch (e) {
      debugPrint('[ScannerService] Send error: $e');
    }
  }

  /// 開始串流（由外部定時呼叫 sendFrame）
  ///
  /// 此方法僅標記狀態，實際送幀由呼叫方控制
  void startStreaming() {
    _isStreaming = true;
  }

  /// 停止串流
  void stopStreaming() {
    _isStreaming = false;
  }

  /// 斷線
  Future<void> disconnect() async {
    await _channel?.sink.close();
    _dispose();
  }

  void _dispose() {
    _channel = null;
    _isStreaming = false;
    _responseController?.close();
    _responseController = null;
  }
}

/// 掃描後端回應
class ScannerResponse {
  /// base64 編碼的 mask 影像
  final String? maskBase64;

  /// 胸徑 cm
  final double? dbh;

  /// 信心度 (0–1)
  final double? confidence;

  ScannerResponse({
    this.maskBase64,
    this.dbh,
    this.confidence,
  });

  Uint8List? get maskBytes {
    if (maskBase64 == null || maskBase64!.isEmpty) return null;
    try {
      return base64.decode(maskBase64!);
    } catch (_) {
      return null;
    }
  }

  factory ScannerResponse.fromJson(Map<String, dynamic> json) {
    double? dbh;
    if (json['dbh'] != null) {
      if (json['dbh'] is num) {
        dbh = (json['dbh'] as num).toDouble();
      } else if (json['dbh'] is String) {
        dbh = double.tryParse(json['dbh'] as String);
      }
    }

    double? confidence;
    if (json['confidence'] != null) {
      if (json['confidence'] is num) {
        confidence = (json['confidence'] as num).toDouble();
      } else if (json['confidence'] is String) {
        confidence = double.tryParse(json['confidence'] as String);
      }
    }

    return ScannerResponse(
      maskBase64: json['mask']?.toString(),
      dbh: dbh,
      confidence: confidence,
    );
  }
}
