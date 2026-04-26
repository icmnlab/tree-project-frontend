import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class AuthGuard extends StatelessWidget {
  final Widget child;
  final bool requireAdmin;
  final String? requiredProject;
  final String? requiredRole; // [T7] 最低角色限制

  const AuthGuard({
    super.key,
    required this.child,
    this.requireAdmin = false,
    this.requiredProject,
    this.requiredRole,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _checkAccess(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError || snapshot.data != true) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // [T7] 未登入 -> /login；權限不足 -> 返回上一頁
if (Navigator.canPop(context)) {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('權限不足，無法進入該頁面')),
              );
            } else {
              Navigator.of(context).pushReplacementNamed('/login');
            }
          });
          return const SizedBox.shrink();
        }

        return child;
      },
    );
  }

  Future<bool> _checkAccess() async {
    final isLoggedIn = await AuthService.isLoggedIn();
    if (!isLoggedIn) return false;

    if (requireAdmin) {
      final isAdmin = await AuthService.isAdmin();
      if (!isAdmin) return false;
    }

    // [T7] 最低角色檢查
    if (requiredRole != null) {
      final ok = await AuthService.hasMinimumRole(requiredRole!);
      if (!ok) return false;
    }

    if (requiredProject != null) {
      final canAccess = await AuthService.canAccessProject(requiredProject!);
      if (!canAccess) return false;
    }

    return true;
  }
}
