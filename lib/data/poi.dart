import 'package:flutter/material.dart';

/// Категория объекта.
///
/// Раньше это был `enum` с семью значениями, вписанными в код, и он разошёлся с
/// базой: три категории в нём не существовали вовсе, а пятнадцати реальных не
/// было. Теперь список — ДАННЫЕ: встроенный набор повторяет таблицу `regions`/
/// вьюхи `v_<категория>`, а при старте приложение один раз спрашивает сервер
/// (`/api/config`) и подменяет его тем, что реально лежит в базе.
///
/// Сравнение идёт по ключу, поэтому `PoiCategory.bank == загруженный bank`
/// даже если подпись и цвет пришли с сервера.
class PoiCategory {
  const PoiCategory(this.key, this.label, this.icon, this.color);

  final String key;
  final String label;
  final IconData icon;
  final Color color;

  // --- Встроенный набор: ровно те категории, по которым в базе есть вьюхи -----
  static const bank = PoiCategory('bank', 'Банк', Icons.account_balance, Color(0xFF08519C));
  static const atm = PoiCategory('atm', 'Банкомат', Icons.local_atm, Color(0xFF2CA02C));
  static const pharmacy = PoiCategory('pharmacy', 'Аптека', Icons.local_pharmacy, Color(0xFF1B9E77));
  static const hotel = PoiCategory('hotel', 'Отель', Icons.hotel, Color(0xFF7B3294));
  static const restaurant = PoiCategory('restaurant', 'Ресторан', Icons.restaurant, Color(0xFFE6550D));
  static const charging = PoiCategory('charging', 'Зарядка', Icons.ev_station, Color(0xFFB8860B));
  static const hospital = PoiCategory('hospital', 'Больница', Icons.local_hospital, Color(0xFFC0392B));
  static const clinic = PoiCategory('clinic', 'Клиника', Icons.medical_services, Color(0xFFC2185B));
  static const taxi = PoiCategory('taxi', 'Такси', Icons.local_taxi, Color(0xFFF39C12));
  static const carRental = PoiCategory('car_rental', 'Прокат авто', Icons.directions_car, Color(0xFF5D4037));
  static const bikeRental = PoiCategory('bike_rental', 'Прокат велосипедов', Icons.pedal_bike, Color(0xFF00796B));
  static const scooterRental = PoiCategory('scooter_rental', 'Прокат самокатов', Icons.electric_scooter, Color(0xFF00838F));
  static const mobileShop = PoiCategory('mobile_shop', 'Салон связи', Icons.smartphone, Color(0xFF3949AB));
  static const airport = PoiCategory('airport', 'Аэропорт', Icons.flight, Color(0xFF0277BD));
  static const railway = PoiCategory('railway', 'Железная дорога', Icons.train, Color(0xFF37474F));
  static const metro = PoiCategory('metro', 'Метро', Icons.subway, Color(0xFF455A64));
  static const tram = PoiCategory('tram', 'Трамвай', Icons.tram, Color(0xFF546E7A));
  static const ferry = PoiCategory('ferry', 'Паром', Icons.directions_boat, Color(0xFF01579B));
  static const luggage = PoiCategory('luggage', 'Камера хранения', Icons.luggage, Color(0xFF6D4C41));

  /// Старые категории-призраки. В базе их нет и результат по ним не находится;
  /// оставлены только чтобы читались старые снимки файлов и тесты.
  static const exchange = PoiCategory('exchange', 'Обмен валюты', Icons.currency_exchange, Color(0xFFB45309));
  static const shop = PoiCategory('shop', 'Магазин', Icons.storefront, Color(0xFF6D28D9));
  static const supermarket = PoiCategory('supermarket', 'Супермаркет', Icons.shopping_cart, Color(0xFF6D28D9));

  /// Встроенный список — то, что показываем, пока сервер не ответил.
  static const _builtIn = <PoiCategory>[
    hotel, restaurant, bank, pharmacy, hospital, clinic, charging, atm, taxi,
    carRental, bikeRental, scooterRental, mobileShop, airport, railway, metro,
    tram, ferry, luggage,
  ];

  static List<PoiCategory> _all = _builtIn;
  static Map<String, PoiCategory> _byKey = {for (final c in _builtIn) c.key: c};

  /// Категории для фильтра: после старта — те, что вернул сервер.
  static List<PoiCategory> get values => _all;

  /// Подменить список тем, что пришёл с сервера. Неизвестные ключи получают
  /// нейтральную подпись и иконку, а не теряются молча.
  static void applyServer(List<PoiCategory> loaded) {
    if (loaded.isEmpty) {
      return;
    }
    _all = List<PoiCategory>.unmodifiable(loaded);
    _byKey = {
      for (final c in _builtIn) c.key: c,
      for (final c in loaded) c.key: c,
    };
  }

  static PoiCategory fromKey(String key) => _byKey[key] ??
      PoiCategory(key, key, Icons.place, const Color(0xFF667085));

  @override
  bool operator ==(Object other) => other is PoiCategory && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'PoiCategory($key)';
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
    this.nameEn = '',
  });

  final int id;
  final String name;
  final PoiCategory category;
  final double lat;
  final double lon;
  final String address;
  final String hours;
  final String phone;

  /// Английское название: из OSM или из кэша переводов на сервере.
  final String nameEn;

  /// Имя для показа. Если исходное имя на непрочитаемом скрипте (иероглифы,
  /// тайский, арабский), а английское есть — показываем английское: иначе
  /// в Китае и Таиланде список нечитаем.
  String get displayName {
    final en = nameEn.trim();
    if (en.isEmpty) return name;
    final readable = RegExp(r'[A-Za-zА-Яа-яЁё]').hasMatch(name);
    return readable ? name : en;
  }

  /// Местное название, когда оно отличается от показанного.
  String get subName {
    final shown = displayName;
    return shown == name ? '' : name;
  }

  /// Сайт объекта из OSM (website / contact:website). Пусто — откроем страницу OSM.
  final String website;

  factory Poi.fromJson(Map<String, dynamic> json) => Poi(
        id: (json['id'] as num).toInt(),
        // Сервер отдаёт `category`, старые снимки в assets — `cat`.
        name: (json['name'] as String? ?? '').trim(),
        category: PoiCategory.fromKey('${json['category'] ?? json['cat']}'),
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        address: (json['addr'] as String? ?? '').trim(),
        hours: (json['hours'] as String? ?? '').trim(),
        phone: (json['phone'] as String? ?? '').trim(),
        website: (json['web'] as String? ?? '').trim(),
        nameEn: (json['nameEn'] as String? ?? '').trim(),
      );
}
