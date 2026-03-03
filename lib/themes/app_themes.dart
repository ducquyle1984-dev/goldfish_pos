import 'package:flutter/material.dart';

/// Centralised theme definitions for Goldfish POS.
///
/// [AppThemes.light]     – standard Material 3 light theme (orange accent)
/// [AppThemes.waterDark] – deep-water dark theme matching the login screen
abstract class AppThemes {
  // Brand colours
  static const Color orange = Color(0xFFFF8C00);
  static const Color navyDeep = Color(0xFF0A1628);
  static const Color navyMid = Color(0xFF0D2B45);
  static const Color navySurface = Color(0xFF122030);
  static const Color navyCard = Color(0xFF152536);
  static const Color oceanBlue = Color(0xFF0F4C75);

  // ── Light theme ──────────────────────────────────────────────────────────
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: orange, primary: orange),
    cardTheme: CardThemeData(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );

  // ── Dark water theme ─────────────────────────────────────────────────────
  static ThemeData get waterDark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: orange,
      onPrimary: Colors.white,
      secondary: oceanBlue,
      onSecondary: Colors.white,
      surface: navySurface,
      onSurface: Colors.white,
      surfaceContainerHighest: navyCard,
      outline: Color(0xFF2A4060),
      outlineVariant: Color(0xFF1E3048),
      error: Color(0xFFFF6B6B),
    ),
    scaffoldBackgroundColor: navyDeep,

    // ── AppBar ──────────────────────────────────────────────────────────
    appBarTheme: const AppBarTheme(
      backgroundColor: navyDeep,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      iconTheme: IconThemeData(color: Colors.white),
      actionsIconTheme: IconThemeData(color: Colors.white70),
    ),

    // ── Navigation Rail ─────────────────────────────────────────────────
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: navyMid,
      selectedIconTheme: const IconThemeData(color: orange),
      selectedLabelTextStyle: const TextStyle(
        color: orange,
        fontWeight: FontWeight.bold,
      ),
      unselectedIconTheme: const IconThemeData(color: Colors.white54),
      unselectedLabelTextStyle: const TextStyle(color: Colors.white54),
      indicatorColor: orange.withOpacity(0.15),
    ),

    // ── Card ────────────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      elevation: 0,
      color: navyCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
    ),

    // ── Drawer ──────────────────────────────────────────────────────────
    drawerTheme: const DrawerThemeData(backgroundColor: navyMid),

    // ── List tiles ──────────────────────────────────────────────────────
    listTileTheme: const ListTileThemeData(
      textColor: Colors.white70,
      iconColor: Colors.white54,
    ),

    // ── Divider ─────────────────────────────────────────────────────────
    dividerTheme: DividerThemeData(color: Colors.white.withOpacity(0.08)),

    // ── Text ────────────────────────────────────────────────────────────
    textTheme: const TextTheme(
      titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      titleMedium: TextStyle(color: Colors.white),
      titleSmall: TextStyle(color: Colors.white70),
      bodyLarge: TextStyle(color: Colors.white),
      bodyMedium: TextStyle(color: Colors.white70),
      bodySmall: TextStyle(color: Color(0xFF8BABC8)),
      labelLarge: TextStyle(color: Colors.white),
      labelSmall: TextStyle(color: Color(0xFF8BABC8)),
    ),

    // ── Input decoration ────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      labelStyle: const TextStyle(color: Colors.white54),
      hintStyle: const TextStyle(color: Colors.white38),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: orange, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFFF6B6B)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1.5),
      ),
      prefixIconColor: Colors.white54,
      suffixIconColor: Colors.white54,
    ),

    // ── Buttons ─────────────────────────────────────────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: orange,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: orange,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: orange,
        side: BorderSide(color: orange.withOpacity(0.6)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: orange),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: Colors.white70),
    ),

    // ── Chips ───────────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      backgroundColor: navyCard,
      labelStyle: const TextStyle(color: Colors.white70),
      side: BorderSide(color: Colors.white.withOpacity(0.1)),
    ),

    // ── Dialog ──────────────────────────────────────────────────────────
    dialogTheme: const DialogThemeData(
      backgroundColor: navyMid,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      contentTextStyle: TextStyle(color: Colors.white70),
    ),

    // ── SnackBar ────────────────────────────────────────────────────────
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: navyCard,
      contentTextStyle: TextStyle(color: Colors.white),
      actionTextColor: orange,
    ),

    // ── Bottom sheet ────────────────────────────────────────────────────
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: navyMid),

    // ── Popup menu ──────────────────────────────────────────────────────
    popupMenuTheme: PopupMenuThemeData(
      color: navyMid,
      textStyle: const TextStyle(color: Colors.white70),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
    ),

    // ── Tab bar ─────────────────────────────────────────────────────────
    tabBarTheme: const TabBarThemeData(
      labelColor: orange,
      unselectedLabelColor: Colors.white54,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: orange, width: 2),
      ),
    ),

    // ── DataTable ───────────────────────────────────────────────────────
    dataTableTheme: DataTableThemeData(
      headingTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
      dataTextStyle: const TextStyle(color: Colors.white70),
      decoration: BoxDecoration(
        color: navyCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
    ),

    // ── Dropdown ────────────────────────────────────────────────────────
    dropdownMenuTheme: const DropdownMenuThemeData(
      menuStyle: MenuStyle(backgroundColor: WidgetStatePropertyAll(navyCard)),
    ),

    // ── Progress indicator ──────────────────────────────────────────────
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: orange),

    // ── Switch / Checkbox / Radio ────────────────────────────────────────
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? orange : Colors.white38,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? orange.withOpacity(0.4)
            : Colors.white12,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? orange : Colors.transparent,
      ),
    ),
  );
}
