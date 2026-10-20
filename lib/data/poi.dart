import 'package:flutter/material.dart';

/// Категория объекта. Значения совпадают с тем, что лежит в `assets/pois.json`
/// и что отдаёт сервер (`/api/search`), поэтому строка из JSON читается один в один.
enum PoiCategory {
  bank('bank', 'Банк', Icons.account_balance, Color(0xFF0F7B6C)),
  atm('atm', 'Банкомат', Icons.local_atm, Color(0xFF1D4ED8)),
  exchange('exchange', 'Обмен валюты', Icons.currency_exchange, Color(0xFFB45309)),
  pharmacy('pharmacy', 'Аптека', Icons.local_pharmacy, Color(0xFFBE123C)),
  shop('shop', 'Магазин', Icons.storefront, Color(0xFF6D28D9)),
  supermarket('supermarket', 'Супермаркет', Icons.shopping_cart, Color(0xFF6D28D9)),
  hotel('hotel', 'Отель', Icons.hotel, Color(0xFF0E7490));

  const PoiCategory(this.key, this.label, this.icon, this.color);

  final String key;
  final String label;
  final IconData icon;
  final Color color;

  static PoiCategory fromKey(String key) => PoiCategory.values.firstWhere(
        (c) => c.key == key,
        orElse: () => PoiCategory.shop,
      );
}

/// Объект на карте. Поля повторяют ответ сервера: id, name, category, lat, lon,
/// address, opening_hours, phone.
class Poi {
  const Poi({
    required this.id,
    required this.name,
    required this.category,
    required this.lat,
    required this.lon,
    this.address = '',
    this.hours = '',
    this.phone = '',
    this.website = '',
  });

  final int id;
  final String name;
  final PoiCategory category;
  final double lat;
  final double lon;
  final String address;
  final String hours;
  final String phone;

  /// Сайт объекта из OSM (website / contact:website). Пусто — откроем страницу OSM.
  final String website;

  factory Poi.fromJson(Map<String, dynamic> json) => Poi(
        id: (json['id'] as num).toInt(),
        name: (json['name'] as String).trim(),
        category: PoiCategory.fromKey(json['cat'] as String),
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        address: (json['addr'] as String? ?? '').trim(),
        hours: (json['hours'] as String? ?? '').trim(),
        phone: (json['phone'] as String? ?? '').trim(),
        website: (json['web'] as String? ?? '').trim(),
      );
}
