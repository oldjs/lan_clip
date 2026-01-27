import 'package:flutter/material.dart';
import '../../theme/desktop_theme.dart';

/// 桌面端背景
class DesktopBackground extends StatelessWidget {
  const DesktopBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                DesktopThemeTokens.backgroundTop,
                DesktopThemeTokens.backgroundBottom,
              ],
            ),
          ),
        ),
        Positioned(
          top: -120,
          right: -80,
          child: _GlowBlob(
            size: 260,
            color: DesktopThemeTokens.glowBlue,
          ),
        ),
        Positioned(
          bottom: -140,
          left: -90,
          child: _GlowBlob(
            size: 280,
            color: DesktopThemeTokens.glowSand,
          ),
        ),
      ],
    );
  }
}

/// 背景光晕
class _GlowBlob extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowBlob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(size),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.45),
              blurRadius: 120,
              spreadRadius: 20,
            ),
          ],
        ),
      ),
    );
  }
}
