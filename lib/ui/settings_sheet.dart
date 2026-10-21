import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Версию подставляет сборочная машина из `pubspec.yaml` — в настройках
/// всегда честный номер, а не забытая в коде строка.
const String appVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: 'не собрана');

/// Настройки: тема и версия приложения.
Future<void> showSettingsSheet(
  BuildContext context, {
  required bool isDark,
  required VoidCallback onToggleTheme,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Настройки',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  isDark ? Icons.light_mode : Icons.dark_mode,
                  color: accent,
                ),
                title: Text(isDark ? 'Светлая тема' : 'Тёмная тема'),
                subtitle: Text('Сейчас: ${isDark ? 'тёмная' : 'светлая'}'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onToggleTheme();
                },
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline),
                title: const Text('StayHunter'),
                subtitle: Text(
                  'Версия $appVersion',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
