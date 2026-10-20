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

/// Построить пеший маршрут через Valhalla (общественный сервер FOSSGIS).
///
/// Ходим пешком, а не на машине: человек приехал в город и идёт по улицам.
/// Возвращает `null`, если служба не ответила или маршрута нет — тогда
/// приложение честно скажет об этом, а не нарисует прямую.
Future<RoutePlan?> planWalkingRoute({
  required LatLng from,
  required LatLng to,
  http.Client? client,
}) async {
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
    response = await (client ?? http.Client())
        .post(
          Uri.parse('https://valhalla1.openstreetmap.de/route'),
          headers: const {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 20));
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
