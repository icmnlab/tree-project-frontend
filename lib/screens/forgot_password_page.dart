import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/locale_service.dart';
import '../constants/colors.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _requestFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();
  final _usernameRequestController = TextEditingController();
  final _usernameResetController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isRequesting = false;
  bool _isResetting = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _usernameRequestController.dispose();
    _usernameResetController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _requestReset() async {
    if (!_requestFormKey.currentState!.validate()) return;
    setState(() => _isRequesting = true);
    try {
      final result = await AuthService.requestPasswordReset(
        _usernameRequestController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ?? context.tr('pwd_request_ok'),
          ),
        ),
      );
      if (result['success'] == true) {
        _usernameResetController.text = _usernameRequestController.text.trim();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  Future<void> _submitReset() async {
    if (!_resetFormKey.currentState!.validate()) return;
    setState(() => _isResetting = true);
    try {
      final result = await AuthService.resetPassword(
        username: _usernameResetController.text,
        code: _codeController.text,
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message']?.toString() ?? context.tr('pwd_reset_ok'),
            ),
          ),
        );
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']?.toString() ?? '重設失敗'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('pwd_title'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr('pwd_hint'),
                style: TextStyle(color: Colors.grey.shade700, height: 1.4),
              ),
              const SizedBox(height: 24),
              _sectionTitle(context.tr('pwd_step_request')),
              const SizedBox(height: 12),
              Form(
                key: _requestFormKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _usernameRequestController,
                      decoration: InputDecoration(
                        labelText: context.tr('login_account'),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty
                              ? context.tr('login_account_required')
                              : null,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _isRequesting ? null : _requestReset,
                      child: _isRequesting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(context.tr('pwd_request_btn')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 24),
              _sectionTitle(context.tr('pwd_step_reset')),
              const SizedBox(height: 12),
              Form(
                key: _resetFormKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _usernameResetController,
                      decoration: InputDecoration(
                        labelText: context.tr('login_account'),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty
                              ? context.tr('login_account_required')
                              : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _codeController,
                      decoration: InputDecoration(
                        labelText: context.tr('pwd_code'),
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) =>
                          v == null || v.trim().isEmpty
                              ? context.tr('pwd_code_required')
                              : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _newPasswordController,
                      obscureText: _obscureNew,
                      decoration: InputDecoration(
                        labelText: context.tr('pwd_new'),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureNew
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () =>
                              setState(() => _obscureNew = !_obscureNew),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.length < 8) {
                          return context.tr('pwd_new_min');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirm,
                      decoration: InputDecoration(
                        labelText: context.tr('pwd_confirm'),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setState(
                              () => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                      validator: (v) {
                        if (v != _newPasswordController.text) {
                          return context.tr('pwd_mismatch');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _isResetting ? null : _submitReset,
                      child: _isResetting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(context.tr('pwd_reset_btn')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.tr('register_back_login')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    );
  }
}
