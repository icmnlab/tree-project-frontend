import 'dart:async';
import 'package:flutter/material.dart';
import '../services/network_service.dart';
import '../constants/colors.dart';

/// 離線提示橫幅 — 無網路時顯示在頁面頂部
///
/// 使用方式：
/// ```dart
/// Column(children: [
///   const NetworkAwareBanner(),
///   Expanded(child: ... ),
/// ])
/// ```
class NetworkAwareBanner extends StatefulWidget {
  const NetworkAwareBanner({super.key});

  @override
  State<NetworkAwareBanner> createState() => _NetworkAwareBannerState();
}

class _NetworkAwareBannerState extends State<NetworkAwareBanner>
    with SingleTickerProviderStateMixin {
  late final StreamSubscription<bool> _sub;
  bool _offline = !NetworkService().isConnected;
  late final AnimationController _animCtrl;
  late final Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);

    if (_offline) _animCtrl.value = 1.0;

    _sub = NetworkService().stream.listen((connected) {
      if (!mounted) return;
      setState(() => _offline = !connected);
      if (_offline) {
        _animCtrl.forward();
      } else {
        // 恢復連線時短暫顯示「已恢復」再收合
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && !_offline) _animCtrl.reverse();
        });
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _slideAnim,
      axisAlignment: -1,
      child: Material(
        elevation: 2,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: _offline ? AppColors.error : AppColors.accent,
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                Icon(
                  _offline ? Icons.wifi_off_rounded : Icons.wifi_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _offline
                        ? '目前無網路連線，部分功能暫時無法使用'
                        : '網路已恢復連線',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (_offline)
                  GestureDetector(
                    onTap: () => NetworkService().checkNow(),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.refresh_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 包裝 Widget：離線時禁用互動並加上半透明遮罩 + 提示
///
/// ```dart
/// NetworkGuard(
///   message: '儲存功能需要網路連線',
///   child: ElevatedButton(onPressed: _save, child: Text('儲存')),
/// )
/// ```
class NetworkGuard extends StatefulWidget {
  final Widget child;
  final String? message;

  const NetworkGuard({
    super.key,
    required this.child,
    this.message,
  });

  @override
  State<NetworkGuard> createState() => _NetworkGuardState();
}

class _NetworkGuardState extends State<NetworkGuard> {
  late final StreamSubscription<bool> _sub;
  bool _offline = !NetworkService().isConnected;

  @override
  void initState() {
    super.initState();
    _sub = NetworkService().stream.listen((connected) {
      if (mounted) setState(() => _offline = !connected);
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_offline) return widget.child;

    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(widget.message ?? '此功能需要網路連線'),
                ),
              ],
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: AbsorbPointer(
        child: Opacity(
          opacity: 0.5,
          child: widget.child,
        ),
      ),
    );
  }
}
