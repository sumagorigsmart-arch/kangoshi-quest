import 'package:flutter/material.dart';

abstract final class QuestColors {
  static const ink = Color(0xff203537);
  static const muted = Color(0xff52676a);
  static const canvas = Color(0xfff3f1e9);
  static const paper = Color(0xfffffdf7);
  static const teal = Color(0xff126b66);
  static const amber = Color(0xffa65e20);
  static const danger = Color(0xffaa3f38);
}

abstract final class QuestSpace {
  static const small = 8.0;
  static const medium = 16.0;
  static const large = 24.0;
  static const radius = 20.0;
  static const maxWidth = 560.0;
}

ThemeData questTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: QuestColors.teal,
    surface: QuestColors.paper,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: QuestColors.canvas,
    appBarTheme: const AppBarTheme(
      backgroundColor: QuestColors.canvas,
      foregroundColor: QuestColors.ink,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: QuestColors.paper,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(QuestSpace.radius),
        side: const BorderSide(color: Color(0xffdedfd3)),
      ),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 34,
        height: 1.2,
        fontWeight: FontWeight.w800,
        color: QuestColors.ink,
      ),
      headlineMedium: TextStyle(
        fontSize: 29,
        height: 1.2,
        fontWeight: FontWeight.w800,
        color: QuestColors.ink,
      ),
      headlineSmall: TextStyle(
        fontSize: 23,
        height: 1.35,
        fontWeight: FontWeight.w700,
        color: QuestColors.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        height: 1.35,
        fontWeight: FontWeight.w700,
        color: QuestColors.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.4,
        fontWeight: FontWeight.w700,
        color: QuestColors.ink,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.65, color: QuestColors.ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: QuestColors.ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}
