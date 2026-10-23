import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import 'poi.dart';

/// Результат поиска с сервера: объекты и название области, по которой искали.
class PoiSearchResult {
  const PoiSearchResult({required this.pois, required this.areaName});

  final List<Poi> pois;
  final String areaName;
}

/// Откуда берутся объекты.
///
/// Основной источник — сервер (`/api/search` по базе PostGIS: 5 млн строк, 49 стран).
/// Локальный файл города остаётся ЗАПАСНЫМ: без сети карта не должна оставаться
/// пустой, но и притворяться, что в файле лежит вся база, нельзя.
class PoiRepository {
  const PoiRepository();

  /// Тот же хост, что у веб-карты: он же проксирует маршруты и геокодер.
  static const String baseUrl = 'https://map.83.220.175.52.nip.io';

  Future<List<Poi>> load(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((item) => Poi.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Поиск по базе. `category` — ключ категории (pharmacy, restaurant…),
  /// `query` — текст названия, `region` — ключ региона из каталога (moscow),
  /// либо прямоугольник видимой области (w/s/e/n + zoom).
  Future<PoiSearchResult> search({
    String? category,
    String? query,
    String? region,
    double? west,
    double? south,
    double? east,
    double? north,
    int? zoom,
    http.Client? client,
  }) async {
    final params = <String, String>{
      if (category != null && category.isNotEmpty) 'category': category,
      if (query != null && query.trim().length >= 2) 'q': query.trim(),
      if (region != null && region.isNotEmpty) 'region': region,
      if (west != null) 'w': '$west',
      if (south != null) 's': '$south',
      if (east != null) 'e': '$east',
      if (north != null) 'n': '$north',
      if (zoom != null) 'zoom': '$zoom',
    };

    final uri = Uri.parse('$baseUrl/api/search').replace(queryParameters: params);
    final ownsClient = client == null;
    final c = client ?? http.Client();
    try {
      final response = await c.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw Exception('search http ${response.statusCode}');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final rows = body['results'] as List<dynamic>? ?? const <dynamic>[];
      final pois = rows
          .map((row) => Poi.fromJson(row as Map<String, dynamic>))
          .toList(growable: false);
      return PoiSearchResult(pois: pois, areaName: '${body['areaName'] ?? ''}');
    } finally {
      if (ownsClient) {
        c.close();
      }
    }
  }
}
