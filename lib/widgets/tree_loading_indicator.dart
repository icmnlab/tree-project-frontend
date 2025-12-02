import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../constants/colors.dart';

/// Elegant tree-themed loading indicator with animated tree icon
/// Features: Growing tree animation, smooth progress bar, nature-inspired design
class TreeLoadingIndicator extends StatefulWidget {
  final String message;
  final Stream<double>? progressStream;
  final bool showTreeAnimation;

  const TreeLoadingIndicator({
    super.key,
    this.message = '載入中...',
    this.progressStream,
    this.showTreeAnimation = true,
  });

  @override
  State<TreeLoadingIndicator> createState() => _TreeLoadingIndicatorState();
}

class _TreeLoadingIndicatorState extends State<TreeLoadingIndicator>
    with TickerProviderStateMixin {
  double _progress = 0.0;
  late AnimationController _treeController;
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotateAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    
    // Tree growing/breathing animation
    _treeController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _treeController, curve: Curves.easeInOut),
    );

    _rotateAnimation = Tween<double>(begin: -0.02, end: 0.02).animate(
      CurvedAnimation(parent: _treeController, curve: Curves.easeInOut),
    );

    // Pulse animation for the ring
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    // Listen to progress stream
    if (widget.progressStream != null) {
      widget.progressStream!.listen((p) {
        if (mounted) {
          setState(() => _progress = p);
        }
      });
    }
  }

  @override
  void dispose() {
    _treeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.neutral900.withValues(alpha: 0.06),
            blurRadius: 32,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated tree icon with pulse rings
          if (widget.showTreeAnimation) ...[
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Pulse rings
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return CustomPaint(
                        size: const Size(120, 120),
                        painter: _PulseRingPainter(
                          progress: _pulseAnimation.value,
                          color: AppColors.accent,
                        ),
                      );
                    },
                  ),
                  // Animated tree container
                  AnimatedBuilder(
                    animation: _treeController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _scaleAnimation.value,
                        child: Transform.rotate(
                          angle: _rotateAnimation.value,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              gradient: AppColors.greenGradient,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.accent.withValues(alpha: 0.3),
                                  blurRadius: 16,
                                  spreadRadius: 0,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.park_rounded,
                              color: AppColors.white,
                              size: 36,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Progress indicator
          if (widget.progressStream != null) ...[
            // Progress percentage
            Text(
              '${(_progress * 100).toInt()}%',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 16),
            // Progress bar
            Container(
              width: double.infinity,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.accentSurface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        width: constraints.maxWidth * _progress,
                        height: 8,
                        decoration: BoxDecoration(
                          gradient: AppColors.greenGradient,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: 0.4),
                              blurRadius: 8,
                              spreadRadius: 0,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ] else if (!widget.showTreeAnimation) ...[
            // Fallback circular progress
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                strokeCap: StrokeCap.round,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                backgroundColor: AppColors.accentSurface,
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Message
          Text(
            widget.message,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.neutral700,
              letterSpacing: -0.2,
            ),
            textAlign: TextAlign.center,
          ),

          // Eco message hint
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.eco_rounded,
                size: 14,
                color: AppColors.neutral400,
              ),
              const SizedBox(width: 4),
              Text(
                '永續碳匯管理系統',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: AppColors.neutral400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Custom painter for pulse ring effect
class _PulseRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _PulseRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    
    // Draw multiple expanding rings
    for (int i = 0; i < 3; i++) {
      final ringProgress = (progress + (i * 0.33)) % 1.0;
      final radius = 30 + (ringProgress * 30);
      final opacity = (1.0 - ringProgress) * 0.3;
      
      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_PulseRingPainter oldDelegate) =>
      progress != oldDelegate.progress;
}
