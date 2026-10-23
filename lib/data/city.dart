import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Прямоугольник области: для города из геокодера, у которого нет ключа региона.
class CityBbox {
  const CityBbox({required this.south, required this.west, required this.north, required this.east});

  final double south;
  final double west;
  final double north;
  final double east;
}

/// Город, по которому сейчас ищем: ключ региона из каталога, точка камеры и (для
/// двух старых городов) файл-снимок на случай, когда сервер недоступен.
class City {
  const City({
    required this.key,
    required this.name,
    required this.country,
    required this.center,
    required this.asset,
    required this.initialZoom,
    this.bbox,
  });

  final String key;
  final String name;

  /// Страна нужна, когда городов сотни: искать проще по двум уровням.
  final String country;
  final LatLng center;

  /// Снимок объектов для офлайна. Пусто — значит данные только с сервера.
  final String asset;

  final double initialZoom;

  /// Область поиска, если место выбрано по названию (геокодер), а не из каталога.
  final CityBbox? bbox;

  /// Место из геокодера: город, которого нет в каталоге (Мюнхен, Киото), или
  /// страна целиком. Ключа региона у него нет — поиск идёт по этой рамке.
  factory City.fromPlace({
    required String name,
    required String country,
    required LatLng center,
    required CityBbox bbox,
  }) =>
      City(
        key: '',
        name: name,
        country: country,
        center: center,
        asset: '',
        initialZoom: _zoomForSpan((bbox.east - bbox.west).abs()),
        bbox: bbox,
      );

  /// Город из каталога сервера: центр — середина рамки, масштаб — по её ширине.
  factory City.fromCatalog(Map<String, dynamic> city, String countryName) {
    final bbox = city['bbox'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final south = (bbox['south'] as num?)?.toDouble() ?? 0;
    final west = (bbox['west'] as num?)?.toDouble() ?? 0;
    final north = (bbox['north'] as num?)?.toDouble() ?? 0;
    final east = (bbox['east'] as num?)?.toDouble() ?? 0;
    return City(
      key: '${city['key']}',
      name: '${city['nameRu'] ?? city['nameEn'] ?? city['key']}',
      country: countryName,
      center: LatLng((south + north) / 2, (west + east) / 2),
      asset: '',
      initialZoom: _zoomForSpan((east - west).abs()),
      bbox: CityBbox(south: south, west: west, north: north, east: east),
    );
  }

  /// Масштаб, при котором рамка города занимает примерно экран телефона.
  static double _zoomForSpan(double spanDegrees) {
    final span = spanDegrees.clamp(0.002, 60.0);
    final zoom = math.log(360 / span * 1.4) / math.ln2;
    return zoom.clamp(8.0, 15.0).toDouble();
  }
}

/// Пока два города с офлайн-снимками. После загрузки каталога список заменяется
/// всем, что есть в базе (49 стран), — эти два остаются запасными.
const _builtInCities = <City>[
  City(
    key: 'moscow',
    name: 'Москва · Центр',
    country: 'Россия',
    center: LatLng(55.7558, 37.6173),
    asset: 'assets/pois_moscow.json',
    initialZoom: 14.2,
  ),
  City(
    key: 'istanbul',
    name: 'Стамбул · Султанахмет',
    country: 'Турция',
    center: LatLng(41.0082, 28.9744),
    asset: 'assets/pois_istanbul.json',
    initialZoom: 14.6,
  ),
];

/// Текущий список городов: сначала встроенные, после старта — из каталога.
List<City> cities = _builtInCities;

/// Каталог регионов с сервера: те же страны и города, что у веб-карты.
Future<void> loadCities({http.Client? client}) async {
  final ownsClient = client == null;
  final c = client ?? http.Client();
  try {
    final response = await c
        .get(Uri.parse('https://map.83.220.175.52.nip.io/api/regions'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      return;
    }
    final rows = jsonDecode(response.body) as List<dynamic>;
    final loaded = <City>[];
    final defaults = <City>[];
    final seen = <String>{};

    for (final row in rows) {
      final country = row as Map<String, dynamic>;
      final countryName = '${country['nameRu'] ?? country['nameEn'] ?? ''}'.trim();
      final isDefault = country['isDefault'] == true;
      for (final cityRow in country['cities'] as List<dynamic>? ?? const <dynamic>[]) {
        final city = City.fromCatalog(cityRow as Map<String, dynamic>, countryName);
        if (city.key.isEmpty || !seen.add(city.key)) {
          continue;
        }
        loaded.add(city);
        if (isDefault) {
          defaults.add(city);
        }
      }
    }

    if (loaded.isEmpty) {
      return;
    }

    // Страна по умолчанию — первой: открываемся туда, где база говорит «начни здесь».
    final ordered = <City>[...defaults, ...loaded.where((city) => !defaults.contains(city))];
    cities = ordered;
  } catch (_) {
    // Сервер не ответил — остаёмся с двумя встроенными городами.
  } finally {
    if (ownsClient) {
      c.close();
    }
  }
}

/// Город и страна по координатам: обратный геокодер. Нужен, чтобы приложение
/// само открывалось там, где человек находится, и искало в его городе.
Future<City?> placeNear(double latitude, double longitude, {http.Client? client}) async {
  final ownsClient = client == null;
  final c = client ?? http.Client();
  try {
    final uri = Uri.parse('https://map.83.220.175.52.nip.io/api/place').replace(queryParameters: {
      'lat': '$latitude',
      'lon': '$longitude',
      'lang': 'ru',
    });
    final response = await c.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      return null;
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final address = body['address'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final name = '${address['city'] ?? address['town'] ?? address['village'] ?? address['municipality'] ?? body['name'] ?? ''}'.trim();
    final country = '${address['country'] ?? ''}'.trim();
    final box = (body['boundingbox'] as List<dynamic>? ?? const <dynamic>[])
        .map((value) => double.tryParse('$value'))
        .toList(growable: false);
    if (name.isEmpty || box.length != 4) {
      return null;
    }
    // Nominatim отдаёт рамку как [юг, север, запад, восток].
    return City.fromPlace(
      name: name,
      country: country,
      center: LatLng(latitude, longitude),
      bbox: CityBbox(south: box[0]!, west: box[2]!, north: box[1]!, east: box[3]!),
    );
  } catch (_) {
    return null;
  } finally {
    if (ownsClient) {
      c.close();
    }
  }
}
