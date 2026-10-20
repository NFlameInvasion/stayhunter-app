import 'package:latlong2/latlong.dart';

const _distance = Distance();

/// Расстояние по прямой между двумя точками, в метрах.
double metersBetween(LatLng from, LatLng to) =>
    _distance.as(LengthUnit.Meter, from, to);

/// «340 м» или «1,2 км» — как человек читает расстояние.
String formatDistance(double meters) {
  if (meters < 950) return '${meters.round()} м';
  final km = meters / 1000;
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} км';
}

/// Сколько идти пешком: спокойный шаг — около 80 м в минуту.
String walkMinutes(double meters) {
  final minutes = (meters / 80).ceil();
  return '$minutes мин';
}
