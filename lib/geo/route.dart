import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Пеший маршрут по улицам: линия, длина и время.
class RoutePlan {
  const RoutePlan({required this.points, required this.meters, required this.seconds});

  final List<LatLng> points;
  final double meters;
  final double seconds;
}

/// Построить пеший маршрут по улицам.
///
/// Два общественных сервера: OSRM и Valhalla. Первый обычно быстрее отвечает,
/// второй — запасной. Если оба молчат, возвращаем `null`: приложение скажет
/// словами, что маршрута нет, а не нарисует прямую.
Future<RoutePlan?> planWalkingRoute({
  required LatLng from,
  required LatLng to,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final first = await _osrm(c, from, to);
  if (first != null) return first;
  return _valhalla(c, from, to);
}

/// OSRM: пеший профиль, геометрия сразу в GeoJSON.
///
/// Сначала идём через свой сервер: с мобильных сетей прямой адрес OSRM
/// часто не отвечает, а сервер в России его достаёт без VPN.
Future<RoutePlan?> _osrm(http.Client client, LatLng from, LatLng to) async {
  const hosts = [
    'https://tiles.83.220.175.52.nip.io/route',
    'https://router.project-osrm.org',
  ];
  for (final host in hosts) {
    final plan = await _osrmFrom(client, host, from, to);
    if (plan != null) return plan;
  }
  return null;
}

Future<RoutePlan?> _osrmFrom(
  http.Client client,
  String host,
  LatLng from,
  LatLng to,
) async {
  final url = Uri.parse(
    '$host/route/v1/foot/'
    '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
    '?overview=full&geometries=geojson',
  );

  final http.Response response;
  try {
    response = await client.get(url).timeout(const Duration(seconds: 8));
  } catch (_) {
    return null;
  }
  if (response.statusCode != 200) return null;

  try {
    final routes = (jsonDecode(response.body) as Map<String, dynamic>)['routes'] as List<dynamic>;
    if (routes.isEmpty) return null;
    final route = routes.first as Map<String, dynamic>;
    final geometry = route['geometry'] as Map<String, dynamic>;
    final coordinates = (geometry['coordinates'] as List<dynamic>).cast<List<dynamic>>();
    final points = coordinates
        .map((pair) => LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble()))
        .toList(growable: false);
    if (points.length < 2) return null;
    return RoutePlan(
      points: points,
      meters: (route['distance'] as num).toDouble(),
      seconds: (route['duration'] as num).toDouble(),
    );
  } catch (_) {
    return null;
  }
}

/// Valhalla (общественный сервер FOSSGIS) — запасной путь.
Future<RoutePlan?> _valhalla(http.Client client, LatLng from, LatLng to) async {
  final body = jsonEncode({
    'locations': [
      {'lat': from.latitude, 'lon': from.longitude},
      {'lat': to.latitude, 'lon': to.longitude},
    ],
    'costing': 'pedestrian',
    'directions_options': {'units': 'kilometers'},
  });

  final http.Response response;
  try {
    response = await client
        .post(
          Uri.parse('https://valhalla1.openstreetmap.de/route'),
          headers: const {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 8));
  } catch (_) {
    return null;
  }
  if (response.statusCode != 200) return null;

  try {
    final trip = (jsonDecode(response.body) as Map<String, dynamic>)['trip'] as Map<String, dynamic>;
    final points = <LatLng>[];
    for (final leg in (trip['legs'] as List).cast<Map<String, dynamic>>()) {
      points.addAll(decodePolyline(leg['shape'] as String, precision: 6));
    }
    if (points.length < 2) return null;
    final summary = trip['summary'] as Map<String, dynamic>;
    return RoutePlan(
      points: points,
      meters: (summary['length'] as num).toDouble() * 1000,
      seconds: (summary['time'] as num).toDouble(),
    );
  } catch (_) {
    return null;
  }
}

/// Раскодировать polyline (формат Google), точность по умолчанию — 1e6.
List<LatLng> decodePolyline(String encoded, {int precision = 6}) {
  final points = <LatLng>[];
  var index = 0;
  var lat = 0;
  var lon = 0;
  final factor = _pow10(precision);

  while (index < encoded.length) {
    var shift = 0;
    var result = 0;
    int byte;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    shift = 0;
    result = 0;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);
    lon += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    points.add(LatLng(lat / factor, lon / factor));
  }
  return points;
}

int _pow10(int power) {
  var value = 1;
  for (var i = 0; i < power; i++) {
    value *= 10;
  }
  return value;
}
