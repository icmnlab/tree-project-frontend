import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class AuthGuard extends StatelessWidget {
  final Widget child;
  final bool requireAdmin;
  final String? requiredProject;

  const AuthGuard({
    super.key,
    required this.child,
    this.requireAdmin = false,
    this.requiredProject,
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
            Navigator.of(context).pushReplacementNamed('/login');
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

    if (requiredProject != null) {
      final canAccess = await AuthService.canAccessProject(requiredProject!);
      if (!canAccess) return false;
    }

    return true;
  }
}
