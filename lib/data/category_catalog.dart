import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'poi.dart';

/// Откуда берётся список категорий: тот же `/api/config`, что кормит веб-карту.
const String kServerConfigUrl = 'https://map.83.220.175.52.nip.io/api/config';

/// Один запрос на старте: список категорий берём с сервера, чтобы фильтр в
/// приложении совпадал с тем, что реально лежит в базе.
///
/// Список меняется редко (новая категория = новая вьюха в базе), поэтому
/// кэшировать между запусками не нужно — достаточно встроенного набора, пока
/// сервер не ответил. Ошибка сети не роняет приложение: фильтр просто остаётся
/// встроенным.
Future<void> loadCategories({http.Client? client}) async {
  final ownsClient = client == null;
  final c = client ?? http.Client();
  try {
    final response = await c
        .get(Uri.parse(kServerConfigUrl))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      return;
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final keys = (body['categories'] as List<dynamic>? ?? const <dynamic>[])
        .map((item) => '$item')
        .where((key) => key.isNotEmpty)
        .toList(growable: false);
    if (keys.isEmpty) {
      return;
    }
    final labels = (body['categoryLabels'] as Map<String, dynamic>? ?? const {});
    final colors = (body['categoryColors'] as Map<String, dynamic>? ?? const {});

    final defs = keys.map((key) {
      final base = PoiCategory.fromKey(key);
      final label = labels[key];
      final hex = colors[key];
      return PoiCategory(
        key,
        label is String && label.trim().isNotEmpty ? label.trim() : base.label,
        base.icon,
        _parseColor(hex is String ? hex : null) ?? base.color,
      );
    }).toList(growable: false);

    PoiCategory.applyServer(defs);
  } catch (_) {
    // Нет сети или сервер молчит — остаёмся со встроенным набором.
  } finally {
    if (ownsClient) {
      c.close();
    }
  }
}

Color? _parseColor(String? hex) {
  if (hex == null) {
    return null;
  }
  final cleaned = hex.replaceAll('#', '').trim();
  if (cleaned.length != 6) {
    return null;
  }
  final value = int.tryParse(cleaned, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}
