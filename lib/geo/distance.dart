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
  // 4 км/ч: столько человек проходит спокойным шагом.
  final minutes = (meters / 66.7).ceil();
  if (minutes < 60) return '$minutes мин';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours ч' : '$hours ч $rest мин';
}
