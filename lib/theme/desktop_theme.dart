import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 桌面端主题
class DesktopTheme {
  static ThemeData build() {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF245D8C),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFD6E8F8),
      onPrimaryContainer: Color(0xFF0C2A3F),
      secondary: Color(0xFF1E7A6B),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFD7F2EC),
      onSecondaryContainer: Color(0xFF0A3B33),
      tertiary: Color(0xFFB56A3E),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFFFE6D4),
      onTertiaryContainer: Color(0xFF4C2A13),
      error: Color(0xFFB3261E),
      onError: Colors.white,
      errorContainer: Color(0xFFF9DEDC),
      onErrorContainer: Color(0xFF410E0B),
      surface: Color(0xFFF6F8FB),
      onSurface: Color(0xFF1A1F24),
      surfaceVariant: Color(0xFFE3E8F0),
      onSurfaceVariant: Color(0xFF434A55),
      outline: Color(0xFFCAD3DE),
      outlineVariant: Color(0xFFE6EBF2),
      shadow: Color(0x1A0B0F14),
      scrim: Color(0x330B0F14),
      inverseSurface: Color(0xFF2A2F36),
      onInverseSurface: Color(0xFFF3F5F8),
      inversePrimary: Color(0xFF9CC9F3),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: DesktopThemeTokens.backgroundBase,
    );

    final textTheme = GoogleFonts.manropeTextTheme(base.textTheme).copyWith(
      titleLarge: GoogleFonts.manrope(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
      titleMedium: GoogleFonts.manrope(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      titleSmall: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      bodyMedium: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
      ),
      bodySmall: GoogleFonts.manrope(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
      ),
      labelLarge: GoogleFonts.manrope(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: DesktopThemeTokens.surfaceCard,
        surfaceTintColor: Colors.transparent,
        shadowColor: colorScheme.shadow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 16,
      ),
      iconTheme: IconThemeData(
        color: colorScheme.onSurfaceVariant,
        size: 20,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.all(colorScheme.outlineVariant),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.onPrimary;
          }
          return colorScheme.surface;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.surfaceVariant;
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.surfaceVariant,
        thumbColor: colorScheme.primary,
        overlayColor: colorScheme.primary.withValues(alpha: 0.12),
        trackHeight: 4,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: colorScheme.primary,
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        labelStyle: textTheme.labelLarge,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
      ),
    );
  }
}

/// 桌面端配色令牌
class DesktopThemeTokens {
  static const Color backgroundBase = Color(0xFFF4F6FB);
  static const Color backgroundTop = Color(0xFFF8FAFF);
  static const Color backgroundBottom = Color(0xFFEEF3F9);
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF1F4F9);
  static const Color glowBlue = Color(0xFFB9D7F0);
  static const Color glowSand = Color(0xFFEFD8C8);
}
