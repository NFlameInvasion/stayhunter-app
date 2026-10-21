import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:stayhunter/data/poi.dart';
import 'package:stayhunter/geo/distance.dart';
import 'package:stayhunter/geo/bearing.dart';
import 'package:stayhunter/search/query_intent.dart';

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
      // 4 км/ч — около 67 метров в минуту.
      expect(walkMinutes(60), '1 мин');
      expect(walkMinutes(140), '3 мин');
      expect(walkMinutes(13000), '3 ч 15 мин');
    });
  });

  group('направление на объект', () {
    test('север — это 0°, восток — 90°', () {
      expect(
        bearingBetween(const LatLng(55.75, 37.61), const LatLng(55.76, 37.61)),
        closeTo(0, 1),
      );
      expect(
        bearingBetween(const LatLng(55.75, 37.61), const LatLng(55.75, 37.62)),
        closeTo(90, 1),
      );
    });

    test('угол поворота: правее — плюс, левее — минус', () {
      expect(relativeBearing(bearing: 10, heading: 0), closeTo(10, 0.001));
      expect(relativeBearing(bearing: 350, heading: 10), closeTo(-20, 0.001));
    });

    test('словами', () {
      expect(directionWords(5), 'Объект прямо');
      expect(directionWords(30), 'Правее на 30°');
      expect(directionWords(-45), 'Левее на 45°');
    });
  });

  group('понимание фразы', () {
    test('«где ближайший банкомат» — это банкомат, а не банк', () {
      expect(understandQuery('где ближайший банкомат').category, PoiCategory.atm);
    });

    test('«обмен валюты в банке» — это обмен', () {
      expect(understandQuery('обмен валюты в банке').category, PoiCategory.exchange);
    });

    test('«нужен банк» — банк', () {
      expect(understandQuery('нужен банк').category, PoiCategory.bank);
    });

    test('«где купить воду» — магазин', () {
      expect(understandQuery('где купить воду').category, PoiCategory.shop);
    });

    test('название объекта — поиск по словам, без категории', () {
      final intent = understandQuery('Ziraat');
      expect(intent.category, isNull);
      expect(intent.cleaned, 'ziraat');
    });
  });
}
