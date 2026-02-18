import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// 全域網路連線狀態服務（Singleton）
///
/// 提供：
/// - [isConnected] 同步讀取目前連線狀態
/// - [stream] 監聽連線變化
/// - [checkNow] 主動檢查一次
class NetworkService {
  NetworkService._();
  static final NetworkService _instance = NetworkService._();
  factory NetworkService() => _instance;

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _connected = true; // 樂觀預設
  bool get isConnected => _connected;

  final _controller = StreamController<bool>.broadcast();

  /// 連線狀態變化串流（true = 有網路, false = 無網路）
  Stream<bool> get stream => _controller.stream;

  /// 初始化（應在 main() 或 MaterialApp 初始化時呼叫一次）
  Future<void> init() async {
    // 初始檢查
    await checkNow();

    // 監聽後續變化
    _subscription ??= _connectivity.onConnectivityChanged.listen((results) {
      final connected = _hasNetwork(results);
      if (connected != _connected) {
        _connected = connected;
        _controller.add(_connected);
        debugPrint('[NetworkService] 連線狀態變化: ${_connected ? "已連線" : "離線"}');
      }
    });
  }

  /// 主動檢查一次連線
  Future<bool> checkNow() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _connected = _hasNetwork(results);
      _controller.add(_connected);
    } catch (e) {
      debugPrint('[NetworkService] checkNow 失敗: $e');
      // 檢查失敗時維持上次狀態
    }
    return _connected;
  }

  bool _hasNetwork(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return !results.every((r) => r == ConnectivityResult.none);
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _controller.close();
  }
}
