import 'package:flutter_test/flutter_test.dart';
import 'package:stayhunter/data/poi.dart';
import 'package:stayhunter/search/query_intent.dart';

/// Как человек говорит на улице: с «где», «покажи», «рядом», в разном роде
/// и числе. Категория должна угадываться без модели, по словарю.
void main() {
  group('категория по фразе', () {
    final cases = <String, PoiCategory>{
      'банк': PoiCategory.bank,
      'покажи ближайшие банки': PoiCategory.bank,
      'где тут банк?': PoiCategory.bank,
      'нужен банк рядом': PoiCategory.bank,
      'банкомат': PoiCategory.atm,
      'где банкомат': PoiCategory.atm,
      'банкоматы рядом со мной': PoiCategory.atm,
      'нужно снять деньги': PoiCategory.atm,
      'снять наличные': PoiCategory.atm,
      'обналичить карту': PoiCategory.atm,
      'ATM': PoiCategory.atm,
      'обмен валюты': PoiCategory.exchange,
      'где обменять валюту': PoiCategory.exchange,
      'нужен обменник': PoiCategory.exchange,
      'поменять деньги': PoiCategory.exchange,
      'какой курс доллара': PoiCategory.exchange,
      'аптека': PoiCategory.pharmacy,
      'ближайшая аптека': PoiCategory.pharmacy,
      'нужны лекарства': PoiCategory.pharmacy,
      'купить таблетки': PoiCategory.pharmacy,
      'супермаркет': PoiCategory.supermarket,
      'гипермаркет рядом': PoiCategory.supermarket,
      'магазин': PoiCategory.shop,
      'продукты': PoiCategory.shop,
      'купить воды': PoiCategory.shop,
      'перекус': PoiCategory.shop,
      'отель': PoiCategory.hotel,
      'гостиница рядом': PoiCategory.hotel,
      'где переночевать': PoiCategory.hotel,
      'хостел': PoiCategory.hotel,
    };

    cases.forEach((phrase, expected) {
      test('«$phrase» → ${expected.label}', () {
        final intent = understandQuery(phrase);
        expect(intent.category, expected);
        expect(intent.understood, isTrue);
        expect(intent.cleaned, isNull);
      });
    });
  });

  group('узкое понятие важнее широкого', () {
    test('«обмен валюты в банке» — это обмен, а не банк', () {
      expect(understandQuery('обмен валюты в банке').category, PoiCategory.exchange);
    });

    test('«банкомат банка» — это банкомат', () {
      expect(understandQuery('банкомат банка').category, PoiCategory.atm);
    });

    test('«супермаркет» не превращается в магазин', () {
      expect(understandQuery('супермаркет').category, PoiCategory.supermarket);
    });
  });

  group('ложные срабатывания', () {
    test('«банкетный зал» — не банк', () {
      final intent = understandQuery('банкетный зал');
      expect(intent.category, isNull);
      expect(intent.cleaned, 'банкетный зал');
    });

    test('«банкет» — не банкомат и не банк', () {
      expect(understandQuery('банкет').category, isNull);
    });

    test('«аптекарский огород» — это аптека по словарю, но текст остаётся', () {
      // Слово «аптекарский» начинается с «аптек»: сознательно считаем аптекой.
      expect(understandQuery('аптекарский огород').category, PoiCategory.pharmacy);
    });
  });

  group('поиск по словам без категории', () {
    test('«покажи мне Тверскую» — служебные слова убраны', () {
      final intent = understandQuery('покажи мне Тверскую');
      expect(intent.category, isNull);
      expect(intent.cleaned, 'тверскую');
    });

    test('«где ближайший рынок» — остаётся «рынок»', () {
      expect(understandQuery('где ближайший рынок').cleaned, 'рынок');
    });

    test('фраза только из служебных слов остаётся целиком', () {
      expect(understandQuery('где рядом').cleaned, 'где рядом');
    });

    test('регистр и лишние пробелы не мешают', () {
      final intent = understandQuery('   АПТЕКА   ');
      expect(intent.category, PoiCategory.pharmacy);
    });

    test('«ё» считается за «е»', () {
      expect(understandQuery('аптёка').category, PoiCategory.pharmacy);
    });

    test('кириллица и латиница в одном запросе: «курс usd»', () {
      expect(understandQuery('курс usd').category, PoiCategory.exchange);
    });

    test('пустая строка — ничего не понято и не ищется', () {
      final intent = understandQuery('   ');
      expect(intent.category, isNull);
      expect(intent.cleaned, isNull);
      expect(intent.understood, isFalse);
    });
  });
}
