import 'package:flutter/material.dart';

import 'data/category_catalog.dart';
import 'theme/app_theme.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Один запрос до первого кадра: список категорий должен совпадать с базой.
  // Сервер не ответил — приложение стартует со встроенным набором.
  await loadCategories();
  runApp(const StayHunterApp());
}

class StayHunterApp extends StatefulWidget {
  const StayHunterApp({super.key});

  @override
  State<StayHunterApp> createState() => _StayHunterAppState();
}

class _StayHunterAppState extends State<StayHunterApp> {
  /// Тема одна на всё приложение: карта и панели меняются вместе.
  bool _dark = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StayHunter',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      home: HomeScreen(
        isDark: _dark,
        onToggleTheme: () => setState(() => _dark = !_dark),
      ),
    );
  }
}
