import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:stayhunter/data/poi.dart';
import 'package:stayhunter/geo/distance.dart';

void main() {
  group('объект из JSON', () {
    test('читается полностью', () {
      final poi = Poi.fromJson({
        'id': 42,
        'name': ' Ziraat Bankası ',
        'cat': 'bank',
        'lat': 41.0082,
        'lon': 28.9744,
        'addr': 'Alemdar Mh.',
        'hours': 'Mo-Fr 09:00-18:00',
        'phone': '+90 212 000 00 00',
      });

      expect(poi.id, 42);
      expect(poi.name, 'Ziraat Bankası');
      expect(poi.category, PoiCategory.bank);
      expect(poi.address, 'Alemdar Mh.');
      expect(poi.hours, 'Mo-Fr 09:00-18:00');
    });

    test('незнакомая категория не роняет разбор', () {
      final poi = Poi.fromJson({
        'id': 1,
        'name': 'Точка',
        'cat': 'что-то новое',
        'lat': 0,
        'lon': 0,
      });
      expect(poi.category, PoiCategory.shop);
    });
  });

  group('расстояние', () {
    test('до ближайшего объекта считается в метрах', () {
      final meters = metersBetween(
        const LatLng(41.0082, 28.9744),
        const LatLng(41.0094, 28.9752),
      );
      expect(meters, greaterThan(100));
      expect(meters, lessThan(200));
    });

    test('метры и километры пишутся по-человечески', () {
      expect(formatDistance(340), '340 м');
      expect(formatDistance(1230), '1,2 км');
    });

    test('минуты пешком округляются вверх', () {
      expect(walkMinutes(80), '1 мин');
      expect(walkMinutes(81), '2 мин');
      expect(walkMinutes(340), '5 мин');
    });
  });
}
