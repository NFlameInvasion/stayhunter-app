import 'package:latlong2/latlong.dart';

/// Город, по которому сейчас ищем. Данные лежат в приложении, поэтому город —
/// это просто набор объектов и точка, куда ставить камеру.
class City {
  const City({
    required this.key,
    required this.name,
    required this.country,
    required this.center,
    required this.asset,
    required this.initialZoom,
  });

  final String key;
  final String name;

  /// Страна нужна, когда городов сотни: искать проще по двум уровням.
  final String country;
  final LatLng center;
  final String asset;
  final double initialZoom;
}

/// Пока два города. Добавить третий — положить файл в assets и дописать строку.
const cities = <City>[
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
