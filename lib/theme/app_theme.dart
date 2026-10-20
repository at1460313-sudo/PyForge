import 'package:flutter/material.dart';

/// The three app themes. Dark is the default; OLED is true black.
enum AppThemeMode { dark, light, oled }

class AppThemes {
  // Brand accents.
  static const Color mint = Color(0xFF7CFFB2);
  static const Color azure = Color(0xFF61AFEF);
  static const Color amber = Color(0xFFE5C07B);
  static const Color coral = Color(0xFFE06C75);

  static ThemeData dark() => _base(
        ColorScheme(
          brightness: Brightness.dark,
          primary: mint,
          onPrimary: const Color(0xFF0B0F12),
          secondary: azure,
          onSecondary: const Color(0xFF0B0F12),
          surface: const Color(0xFF1B1E24),
          onSurface: const Color(0xFFD7DAE0),
          surfaceContainerHighest: const Color(0xFF242830),
          error: coral,
          onError: Colors.white,
          outline: const Color(0xFF3A3F48),
        ),
        scaffold: const Color(0xFF14161B),
      );

  static ThemeData oled() => _base(
        ColorScheme(
          brightness: Brightness.dark,
          primary: mint,
          onPrimary: const Color(0xFF0B0F12),
          secondary: azure,
          onSecondary: const Color(0xFF0B0F12),
          surface: const Color(0xFF0A0A0C),
          onSurface: const Color(0xFFD7DAE0),
          surfaceContainerHighest: const Color(0xFF131318),
          error: coral,
          onError: Colors.white,
          outline: const Color(0xFF232329),
        ),
        scaffold: Colors.black,
      );

  static ThemeData light() => _base(
        ColorScheme(
          brightness: Brightness.light,
          primary: const Color(0xFF0E8A5F),
          onPrimary: Colors.white,
          secondary: const Color(0xFF2E6FB7),
          onSecondary: Colors.white,
          surface: Colors.white,
          onSurface: const Color(0xFF1C1F24),
          surfaceContainerHighest: const Color(0xFFEDF0F3),
          error: const Color(0xFFC0392B),
          onError: Colors.white,
          outline: const Color(0xFFC9CDD3),
        ),
        scaffold: const Color(0xFFF6F7F9),
      );

  static ThemeData _base(ColorScheme scheme, {required Color scaffold}) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scaffold,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.onlySelected,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scaffold,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: scheme.onSurface.withValues(alpha: 0.6)),
        selectedLabelTextStyle: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.4)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      tooltipTheme: const TooltipThemeData(preferBelow: true),
    );
  }
}
