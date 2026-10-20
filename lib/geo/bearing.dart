import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Направление от одной точки к другой: азимут в градусах, 0 — север.
double bearingBetween(LatLng from, LatLng to) {
  final lat1 = from.latitude * math.pi / 180;
  final lat2 = to.latitude * math.pi / 180;
  final dLon = (to.longitude - from.longitude) * math.pi / 180;

  final y = math.sin(dLon) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Куда повернуть, если смотреть по направлению телефона.
///
/// Возвращает угол от -180 до 180: положительный — объект правее, отрицательный —
/// левее. Именно это человек и делает: поворачивается на этот угол.
double relativeBearing({required double bearing, required double heading}) {
  var diff = (bearing - heading) % 360;
  if (diff > 180) diff -= 360;
  if (diff < -180) diff += 360;
  return diff;
}

/// Словами: «прямо», «правее на 30°», «левее на 45°».
String directionWords(double relative) {
  final angle = relative.abs().round();
  if (angle <= 12) return 'Объект прямо';
  return relative > 0 ? 'Правее на $angle°' : 'Левее на $angle°';
}
