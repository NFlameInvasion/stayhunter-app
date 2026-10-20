import 'package:flutter/material.dart';

/// Подложка карты: светлая и тёмная, без подписей и мелочи.
///
/// Палитра повторяет игровые варианты StayHunter: спокойная земля, вода, дороги
/// и ничего лишнего. Подписи и значки объектов — наши, поэтому карта не спорит
/// с ними за внимание.
class Basemap {
  const Basemap({required this.url, required this.grade});

  /// Шаблон тайлов OSM-подложки CARTO без подписей.
  final String url;

  /// Лёгкая цветокоррекция: подтягивает чужую картинку к нашей палитре.
  final ColorFilter grade;

  static const light = Basemap(
    url: 'https://basemaps.cartocdn.com/light_nolabels/{z}/{x}/{y}@2x.png',
    // Чуть теплее и мягче: земля ближе к #f6f3ee, чем к белому листу.
    grade: ColorFilter.matrix([
      0.98, 0.00, 0.00, 0, 3,
      0.00, 0.97, 0.00, 0, 2,
      0.00, 0.00, 0.93, 0, 1,
      0.00, 0.00, 0.00, 1, 0,
    ]),
  );

  static const dark = Basemap(
    url: 'https://basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}@2x.png',
    // Ночная палитра StayHunter глуше и холоднее обычной тёмной подложки.
    grade: ColorFilter.matrix([
      0.62, 0.00, 0.00, 0, 4,
      0.00, 0.66, 0.00, 0, 7,
      0.00, 0.00, 0.74, 0, 10,
      0.00, 0.00, 0.00, 1, 0,
    ]),
  );

  static Basemap of(bool isDark) => isDark ? dark : light;
}
