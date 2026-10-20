import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'poi.dart';

/// Откуда берутся объекты.
///
/// Сейчас — собранный заранее файл по одному городу (Стамбул, Султанахмет).
/// Когда сервер будет доступен, этот же класс начнёт спрашивать `/api/search`
/// и `/api/pois`; интерфейс выше по коду не изменится.
class PoiRepository {
  const PoiRepository();

  Future<List<Poi>> load() async {
    final raw = await rootBundle.loadString('assets/pois.json');
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((item) => Poi.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }
}
