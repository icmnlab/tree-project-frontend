import 'package:flutter/material.dart';

class GlobalKeys {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  // [Bug B 修復] 全域 RouteObserver，讓頁面能訂閱 didPopNext 等事件
  // (例如 MapPage 從別頁返回時強制刷新邊界)
  static final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();
}
