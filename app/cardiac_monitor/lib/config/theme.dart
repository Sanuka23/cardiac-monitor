import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const _seed = Color(0xFF00BFA5); // teal accent

  static final darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorSchemeSeed: _seed,
    scaffoldBackgroundColor: const Color(0xFF0D1117),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
    cardTheme: CardThemeData(
      color: const Color(0xFF161B22),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF161B22),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF161B22),
      selectedItemColor: Color(0xFF00BFA5),
      unselectedItemColor: Color(0xFF8B949E),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0D1117),
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
    ),
  );

  // Risk level colors
  static const Color riskNormal = Color(0xFF4CAF50);
  static const Color riskLow = Color(0xFF8BC34A);
  static const Color riskModerate = Color(0xFFFFC107);
  static const Color riskElevated = Color(0xFFFF9800);
  static const Color riskHigh = Color(0xFFF44336);

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
}
