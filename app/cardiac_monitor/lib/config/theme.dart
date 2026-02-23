import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ─── Light Theme ─────────────────────────────────────────────
  static final lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: const Color(0xFF0D9488),
    scaffoldBackgroundColor: const Color(0xFFF2F4F7),
    textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.light().textTheme),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF8F9FA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF0D9488), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: Color(0xFF0D9488),
      unselectedItemColor: Color(0xFF9CA3AF),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFF2F4F7),
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      foregroundColor: Color(0xFF1A1D21),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFE5E7EB),
      thickness: 1,
    ),
  );

  // ─── Dark Theme ──────────────────────────────────────────────
  static final darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorSchemeSeed: const Color(0xFF14B8A6),
    scaffoldBackgroundColor: const Color(0xFF0F1419),
    textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme),
    cardTheme: CardThemeData(
      color: const Color(0xFF1A1F26),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1A1F26),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2D333B)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2D333B)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF14B8A6), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: const Color(0xFF14B8A6),
        foregroundColor: Colors.white,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF1A1F26),
      selectedItemColor: Color(0xFF14B8A6),
      unselectedItemColor: Color(0xFF6B7280),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0F1419),
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      foregroundColor: Color(0xFFE8ECF0),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF2D333B),
      thickness: 1,
    ),
  );

  // ─── Semantic Colors (same in both themes) ──────────────────
  static const Color riskNormal = Color(0xFF22C55E);
  static const Color riskLow = Color(0xFF84CC16);
  static const Color riskModerate = Color(0xFFEAB308);
  static const Color riskElevated = Color(0xFFF97316);
  static const Color riskHigh = Color(0xFFEF4444);

  static const Color hrColor_ = Color(0xFFEF4444);
  static const Color spo2Color_ = Color(0xFF3B82F6);

  static Color riskColor(double score) {
    if (score < 0.2) return riskNormal;
    if (score < 0.4) return riskLow;
    if (score < 0.6) return riskModerate;
    if (score < 0.8) return riskElevated;
    return riskHigh;
  }

  static Color hrColor(double hr) {
    if (hr < 1) return Colors.grey;
    if (hr >= 60 && hr <= 100) return riskNormal;
    if (hr >= 50 && hr <= 110) return riskModerate;
    return riskHigh;
  }

  static Color spo2Color(int spo2) {
    if (spo2 == 0) return Colors.grey;
    if (spo2 >= 95) return riskNormal;
    if (spo2 >= 90) return riskModerate;
    return riskHigh;
  }

  // ─── Theme-Aware Color Helpers ──────────────────────────────
  static Color accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? const Color(0xFF0D9488)
          : const Color(0xFF14B8A6);

  static Color cardBackground(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? Colors.white
          : const Color(0xFF1A1F26);

  static Color textPrimary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? const Color(0xFF1A1D21)
          : const Color(0xFFE8ECF0);

  static Color textSecondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? const Color(0xFF6B7280)
          : const Color(0xFF8B949E);

  static Color textTertiary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? const Color(0xFF9CA3AF)
          : const Color(0xFF6B7280);

  static Color surfaceVariant(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? const Color(0xFFF8F9FA)
          : const Color(0xFF21262D);

  static Color dividerColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? const Color(0xFFE5E7EB)
          : const Color(0xFF2D333B);

  // Vitals-specific tinted backgrounds
  static Color hrBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? const Color(0xFFFEF2F2)
          : const Color(0xFF2D1B1B);

  static Color spo2Bg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? const Color(0xFFEFF6FF)
          : const Color(0xFF1B2333);

  static Color accentBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? const Color(0xFFCCFBF1)
          : const Color(0xFF0D3D38);
}

class AppGradients {
  static const LinearGradient hr = LinearGradient(
    colors: [Color(0xFFEF4444), Color(0xFFF97316)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient spo2 = LinearGradient(
    colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient risk = LinearGradient(
    colors: [Color(0xFFF97316), Color(0xFFEF4444)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient primary = LinearGradient(
    colors: [Color(0xFF0D9488), Color(0xFF06B6D4)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
}

class CardStyles {
  static BoxDecoration card(BuildContext context, {double borderRadius = 16}) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return BoxDecoration(
      color: AppTheme.cardBackground(context),
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: isLight
          ? const [
              BoxShadow(
                color: Color(0x0F000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ]
          : const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
    );
  }

  static BoxDecoration elevated(BuildContext context,
      {double borderRadius = 16}) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return BoxDecoration(
      color: AppTheme.cardBackground(context),
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: isLight
          ? const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ]
          : const [
              BoxShadow(
                color: Color(0x4D000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
    );
  }
}
