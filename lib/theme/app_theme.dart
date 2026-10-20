import 'package:flutter/material.dart';

/// Общий цвет приложения. Он же — цвет маршрута и акцентов.
const accent = Color(0xFF0F7B6C);

/// Две темы. Карта и интерфейс меняются вместе: ночью светлая карта бьёт по глазам,
/// днём тёмная читается хуже.
ThemeData buildAppTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness);
  final isLight = brightness == Brightness.light;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: isLight ? const Color(0xFFF5F7FA) : const Color(0xFF0B0F14),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: accent),
    ),
  );
}
