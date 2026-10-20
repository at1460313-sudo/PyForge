import 'package:flutter/material.dart';

/// The three app themes. Dark is the default; OLED is true black.
enum AppThemeMode { dark, light, oled }

/// Monospace family used for every piece of code in the app (bundled, no
/// ligatures so `!=` / `->` are shown exactly as typed).
const String kMonoFont = 'JetBrainsMono';

/// Semantic colors that are not part of Material's [ColorScheme].
extension AppColors on ColorScheme {
  bool get isDark => brightness == Brightness.dark;

  /// Secondary text. Kept at >= 4.5:1 contrast on every surface (the old
  /// 40-60 % opacity greys were too faint to read outdoors).
  Color get muted => onSurface.withValues(alpha: isDark ? 0.72 : 0.70);

  /// Hints, captions, disabled-ish text (still >= 3:1).
  Color get faint => onSurface.withValues(alpha: isDark ? 0.55 : 0.55);

  /// Warm accent used for streaks / fire.
  Color get flame => isDark ? AppThemes.amber : const Color(0xFFD97706);

  /// Success green (completed lessons / challenges).
  Color get success =>
      isDark ? const Color(0xFF5FE3A1) : const Color(0xFF0E8A5F);

  /// Violet accent used for challenges / achievements.
  Color get violet =>
      isDark ? const Color(0xFFB794F6) : const Color(0xFF7C3AED);

  /// A tinted fill for an accent color (icon tiles, chips).
  Color tint(Color accent, [double a = 0.16]) => accent.withValues(alpha: a);
}

class AppThemes {
  // Brand accents.
  static const Color mint = Color(0xFF7CFFB2);
  static const Color azure = Color(0xFF61AFEF);
  static const Color amber = Color(0xFFF2C46B);
  static const Color coral = Color(0xFFFF7B86);

  static ThemeData dark() => _base(
        ColorScheme(
          brightness: Brightness.dark,
          primary: mint,
          onPrimary: const Color(0xFF06231A),
          primaryContainer: const Color(0xFF1E3F33),
          onPrimaryContainer: const Color(0xFFB8FFD9),
          secondary: azure,
          onSecondary: const Color(0xFF07182B),
          secondaryContainer: const Color(0xFF223449),
          onSecondaryContainer: const Color(0xFFCBE3FA),
          tertiary: const Color(0xFFB794F6),
          surface: const Color(0xFF181B22),
          onSurface: const Color(0xFFE3E6EC),
          surfaceContainerHighest: const Color(0xFF232731),
          surfaceContainerHigh: const Color(0xFF1F232C),
          error: coral,
          onError: const Color(0xFF2B0A0E),
          outline: const Color(0xFF343A47),
          outlineVariant: const Color(0xFF2A2F3A),
        ),
        scaffold: const Color(0xFF0F1115),
      );

  static ThemeData oled() => _base(
        ColorScheme(
          brightness: Brightness.dark,
          primary: mint,
          onPrimary: const Color(0xFF06231A),
          primaryContainer: const Color(0xFF16352B),
          onPrimaryContainer: const Color(0xFFB8FFD9),
          secondary: azure,
          onSecondary: const Color(0xFF07182B),
          secondaryContainer: const Color(0xFF1B2C40),
          onSecondaryContainer: const Color(0xFFCBE3FA),
          tertiary: const Color(0xFFB794F6),
          surface: const Color(0xFF0B0B0E),
          onSurface: const Color(0xFFE3E6EC),
          surfaceContainerHighest: const Color(0xFF16161C),
          surfaceContainerHigh: const Color(0xFF111116),
          error: coral,
          onError: const Color(0xFF2B0A0E),
          outline: const Color(0xFF2A2A32),
          outlineVariant: const Color(0xFF202026),
        ),
        scaffold: Colors.black,
      );

  static ThemeData light() => _base(
        ColorScheme(
          brightness: Brightness.light,
          primary: const Color(0xFF0B7A55),
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFCDF1E1),
          onPrimaryContainer: const Color(0xFF053D2B),
          secondary: const Color(0xFF2563EB),
          onSecondary: Colors.white,
          secondaryContainer: const Color(0xFFDCE7FC),
          onSecondaryContainer: const Color(0xFF12307A),
          tertiary: const Color(0xFF7C3AED),
          surface: Colors.white,
          onSurface: const Color(0xFF1A1D23),
          surfaceContainerHighest: const Color(0xFFECEFF3),
          surfaceContainerHigh: const Color(0xFFF2F4F7),
          error: const Color(0xFFC62828),
          onError: Colors.white,
          outline: const Color(0xFFC4CAD3),
          outlineVariant: const Color(0xFFDDE1E7),
        ),
        scaffold: const Color(0xFFF4F6F9),
      );

  static ThemeData _base(ColorScheme scheme, {required Color scaffold}) {
    final ThemeData seed = ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
    );
    // A readable, phone-first type scale (body text >= 14.5 sp).
    final TextTheme text = seed.textTheme
        .copyWith(
          headlineMedium: seed.textTheme.headlineMedium!.copyWith(
              fontSize: 28, fontWeight: FontWeight.w800, height: 1.15),
          headlineSmall: seed.textTheme.headlineSmall!.copyWith(
              fontSize: 24, fontWeight: FontWeight.w800, height: 1.2),
          titleLarge: seed.textTheme.titleLarge!.copyWith(
              fontSize: 20, fontWeight: FontWeight.w800, height: 1.25),
          titleMedium: seed.textTheme.titleMedium!.copyWith(
              fontSize: 16.5, fontWeight: FontWeight.w700, height: 1.3),
          titleSmall: seed.textTheme.titleSmall!.copyWith(
              fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.3),
          bodyLarge: seed.textTheme.bodyLarge!.copyWith(fontSize: 16, height: 1.45),
          bodyMedium: seed.textTheme.bodyMedium!.copyWith(fontSize: 14.5, height: 1.45),
          bodySmall: seed.textTheme.bodySmall!.copyWith(fontSize: 13, height: 1.4),
          labelLarge: seed.textTheme.labelLarge!.copyWith(
              fontSize: 14.5, fontWeight: FontWeight.w700, letterSpacing: 0.1),
          labelMedium: seed.textTheme.labelMedium!
              .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
          labelSmall: seed.textTheme.labelSmall!.copyWith(
              fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.3),
        )
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    final RoundedRectangleBorder cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: scheme.outlineVariant),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 60,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        indicatorShape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        height: 74,
        // Always show labels: icons alone were ambiguous (6 unlabeled icons).
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
            IconThemeData(
                size: 25,
                color: s.contains(WidgetState.selected)
                    ? scheme.primary
                    : scheme.muted)),
        labelTextStyle: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
            text.labelLarge!.copyWith(
                fontSize: 12,
                fontWeight: s.contains(WidgetState.selected)
                    ? FontWeight.w800
                    : FontWeight.w600,
                color: s.contains(WidgetState.selected)
                    ? scheme.primary
                    : scheme.muted)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: scheme.muted),
        selectedLabelTextStyle:
            text.labelLarge!.copyWith(color: scheme.primary, fontWeight: FontWeight.w800),
        unselectedLabelTextStyle:
            text.labelLarge!.copyWith(color: scheme.muted, fontWeight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: cardShape,
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.muted,
        minVerticalPadding: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(14),
        ),
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.muted,
        labelStyle:
            text.labelLarge!.copyWith(fontSize: 13.5, fontWeight: FontWeight.w800),
        unselectedLabelStyle:
            text.labelLarge!.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
        overlayColor: WidgetStatePropertyAll<Color>(
            scheme.primary.withValues(alpha: 0.08)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.primary.withValues(alpha: 0.18),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: text.labelLarge!.copyWith(
            fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(52, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          textStyle: text.labelLarge!.copyWith(fontSize: 15, fontWeight: FontWeight.w800),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(52, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: text.labelLarge!.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
          side: BorderSide(color: scheme.outline),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle:
              text.labelLarge!.copyWith(fontSize: 14.5, fontWeight: FontWeight.w700),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          iconSize: 24,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 3,
        extendedTextStyle:
            text.labelLarge!.copyWith(fontSize: 15, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: text.labelLarge!.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
          side: BorderSide(color: scheme.outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: text.labelLarge!.copyWith(color: scheme.faint),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.8),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: text.titleLarge,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.horizontal(right: Radius.circular(28))),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        linearMinHeight: 8,
        borderRadius: BorderRadius.circular(8),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: text.labelLarge!.copyWith(color: scheme.onSurface, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      tooltipTheme: const TooltipThemeData(preferBelow: true),
    );
  }
}
