import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../tree_input_page.dart';
import '../tree_input_page_v2.dart';

/// Modern minimalist dialog for selecting tree input mode
/// Features: Glassmorphism effect, smooth animations, clean typography
class AddTreeSelectionDialog extends StatelessWidget {
  final Map<String, dynamic> initialData;
  final Function() onDataChanged;

  const AddTreeSelectionDialog({
    super.key,
    this.initialData = const {},
    required this.onDataChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.neutral900.withValues(alpha: 0.08),
              blurRadius: 32,
              spreadRadius: 0,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with gradient accent
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.accent.withValues(alpha: 0.08),
                    AppColors.primary.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: AppColors.greenGradient,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.park_rounded,
                      color: AppColors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '選擇新增模式',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.neutral900,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '請選擇適合您的輸入方式',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColors.neutral600,
                    ),
                  ),
                ],
              ),
            ),

            // Options
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Column(
                children: [
                  _ModeOptionCard(
                    icon: Icons.article_rounded,
                    iconColor: AppColors.accent,
                    iconBgColor: AppColors.accentSurface,
                    title: '標準模式',
                    subtitle: '傳統輸入介面，前端生成編號',
                    badge: 'V1',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => TreeInputPage(treeData: initialData),
                        ),
                      ).then((_) => onDataChanged());
                    },
                  ),
                  const SizedBox(height: 12),
                  _ModeOptionCard(
                    icon: Icons.bolt_rounded,
                    iconColor: AppColors.primary,
                    iconBgColor: AppColors.primarySurface,
                    title: '快速模式',
                    subtitle: '優化輸入體驗，後端生成編號',
                    badge: 'V2 Beta',
                    badgeColor: AppColors.tipcTeal,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => TreeInputPageV2(treeData: initialData),
                        ),
                      ).then((_) => onDataChanged());
                    },
                  ),
                ],
              ),
            ),

            // Cancel button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  '取消',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.neutral500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void show(
    BuildContext context, {
    Map<String, dynamic> initialData = const {},
    required Function() onDataChanged,
  }) {
    showDialog(
      context: context,
      barrierColor: AppColors.neutral900.withValues(alpha: 0.4),
      builder: (context) => AddTreeSelectionDialog(
        initialData: initialData,
        onDataChanged: onDataChanged,
      ),
    );
  }
}

/// Reusable mode option card with hover effect
class _ModeOptionCard extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String subtitle;
  final String badge;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _ModeOptionCard({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.subtitle,
    required this.badge,
    this.badgeColor,
    required this.onTap,
  });

  @override
  State<_ModeOptionCard> createState() => _ModeOptionCardState();
}

class _ModeOptionCardState extends State<_ModeOptionCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _isPressed 
              ? AppColors.neutral100 
              : AppColors.neutral50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isPressed 
                ? widget.iconColor.withValues(alpha: 0.3)
                : AppColors.neutral200,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: widget.iconBgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                widget.icon,
                color: widget.iconColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.neutral900,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: (widget.badgeColor ?? AppColors.accent)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.badge,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: widget.badgeColor ?? AppColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: AppColors.neutral600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: AppColors.neutral400,
            ),
          ],
        ),
      ),
    );
  }
}
