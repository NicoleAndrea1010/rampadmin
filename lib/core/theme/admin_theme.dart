import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

abstract final class AdminTheme {
  static ThemeData get lightTheme => _build(
    brightness: Brightness.light,
    scaffold: AppColors.bgLight,
    surface: AppColors.cardLight,
    text: AppColors.textPrimary,
    muted: AppColors.textSecondary,
    border: AppColors.borderLight,
    primary: AppColors.primaryBlue,
  );

  static ThemeData get darkTheme => _build(
    brightness: Brightness.dark,
    scaffold: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    text: AppColors.darkText,
    muted: AppColors.darkMuted,
    border: AppColors.darkBorder,
    primary: AppColors.darkPrimary,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color scaffold,
    required Color surface,
    required Color text,
    required Color muted,
    required Color border,
    required Color primary,
  }) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
        ).copyWith(
          primary: primary,
          surface: surface,
          error: AppColors.error,
          outline: border,
        );
    final baseText = GoogleFonts.poppinsTextTheme(
      brightness == Brightness.light
          ? ThemeData.light().textTheme
          : ThemeData.dark().textTheme,
    ).apply(bodyColor: text, displayColor: text);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      textTheme: baseText.copyWith(
        bodySmall: baseText.bodySmall?.copyWith(fontSize: 12, color: muted),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(44, 48),
          shape: RoundedRectangleBorder(
          ),
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 48),
          shape: RoundedRectangleBorder(
          ),
        ),
      ),
      dividerColor: border,
      dataTableTheme: DataTableThemeData(
        headingTextStyle: GoogleFonts.poppins(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: muted,
        ),
        dataTextStyle: GoogleFonts.poppins(fontSize: 12, color: text),
        headingRowColor: WidgetStatePropertyAll(scaffold),
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: GoogleFonts.poppins(fontSize: 12, color: Colors.white),
      ),
    );
  }
}
