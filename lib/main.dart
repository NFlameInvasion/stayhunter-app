import 'package:flutter/material.dart';

import 'ui/home_screen.dart';

void main() => runApp(const StayHunterApp());

class StayHunterApp extends StatelessWidget {
  const StayHunterApp({super.key});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF0F7B6C);
    return MaterialApp(
      title: 'StayHunter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: accent),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
