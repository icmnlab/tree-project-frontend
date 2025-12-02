import 'package:flutter/material.dart';
import '../constants/colors.dart';

/// Modern loading indicator with pulsing animation
/// Features: Smooth animations, customizable appearance, clean design
class LoadingIndicator extends StatefulWidget {
  final String? message;
  final LoadingSize size;
  final Color? color;
  final bool showBackground;

  const LoadingIndicator({
    super.key,
    this.message,
    this.size = LoadingSize.medium,
    this.color,
    this.showBackground = false,
  });

  @override
  State<LoadingIndicator> createState() => _LoadingIndicatorState();
}

class _LoadingIndicatorState extends State<LoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _fadeAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _indicatorSize {
    switch (widget.size) {
      case LoadingSize.small:
        return 24;
      case LoadingSize.medium:
        return 40;
      case LoadingSize.large:
        return 56;
    }
  }

  double get _strokeWidth {
    switch (widget.size) {
      case LoadingSize.small:
        return 2.5;
      case LoadingSize.medium:
        return 3.5;
      case LoadingSize.large:
        return 4.5;
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.color ?? AppColors.primary;

    Widget indicator = Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Opacity(
                  opacity: _fadeAnimation.value,
                  child: Container(
                    width: _indicatorSize + 24,
                    height: _indicatorSize + 24,
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: SizedBox(
                        width: _indicatorSize,
                        height: _indicatorSize,
                        child: CircularProgressIndicator(
                          strokeWidth: _strokeWidth,
                          strokeCap: StrokeCap.round,
                          valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                          backgroundColor: primaryColor.withValues(alpha: 0.15),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (widget.message != null) ...[
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: _fadeAnimation,
              builder: (context, child) {
                return Opacity(
                  opacity: 0.7 + (_fadeAnimation.value * 0.3),
                  child: Text(
                    widget.message!,
                    style: TextStyle(
                      fontSize: widget.size == LoadingSize.small ? 13 : 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.neutral700,
                      letterSpacing: -0.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );

    if (widget.showBackground) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.neutral900.withValues(alpha: 0.06),
              blurRadius: 24,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: indicator,
      );
    }

    return indicator;
  }
}

/// Size variants for loading indicator
enum LoadingSize { small, medium, large }
