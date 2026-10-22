import '../data/poi.dart';

/// Что человек попросил словами.
///
/// Правила простые и предсказуемые — как и в серверном разборе StayHunter:
/// категорию выбирает словарь, а не модель. Модель (DeepSeek) позже будет
/// разбирать совсем вольные фразы, но и тогда категория останется проверяемой.
class SearchIntent {
  const SearchIntent({this.category, this.cleaned});

  /// Категория, если фраза её называет.
  final PoiCategory? category;

  /// Что искать по словам, если категория не распознана.
  final String? cleaned;

  bool get understood => category != null;
}

/// Слова, которые человек говорит, но которые не помогают искать:
/// «где», «покажи», «ближайший». Без них текстовый поиск находит больше.
const _fillers = {
  'где',
  'покажи',
  'покажите',
  'найди',
  'найдите',
  'подскажи',
  'подскажите',
  'мне',
  'нужен',
  'нужна',
  'нужно',
  'нужны',
  'ближайший',
  'ближайшая',
  'ближайшее',
  'ближайшие',
  'ближайшую',
  'рядом',
  'пожалуйста',
  'есть',
  'хочу',
  'можно',
  'пожалуй',
  'тут',
  'здесь',
};

/// Понять фразу так, как её говорит человек на улице.
///
/// Порядок проверок важен: «банкомат» содержит «банк», а «обмен валюты в банке» —
/// два слова сразу. Поэтому более узкие понятия проверяются раньше широких.
SearchIntent understandQuery(String text) {
  final t = text.toLowerCase().replaceAll('ё', 'е').trim();
  if (t.isEmpty) return const SearchIntent();

  bool has(String pattern) => RegExp(pattern).hasMatch(t);

  if (has(r'банкомат|снять наличн|снимать наличн|наличн|обналич|'
      r'снять деньг|снимать деньг|(^|[^а-я])атм([^а-я]|$)|(^|[^a-z])atm([^a-z]|$)')) {
    return const SearchIntent(category: PoiCategory.atm);
  }
  if (has(r'обмен|обменник|валют|менял|менять деньг|курс')) {
    // Обмена валюты как отдельной категории в базе нет — ближайшее к смыслу
    // «поменять деньги» это банк.
    return const SearchIntent(category: PoiCategory.bank);
  }
  // «банкет» и «банковский» — не банк: после «банк» не должно идти «ет».
  if (has(r'банк(?!ет)')) {
    return const SearchIntent(category: PoiCategory.bank);
  }
  if (has(r'аптек|лекарств|таблет|медикам|зеленый крест')) {
    return const SearchIntent(category: PoiCategory.pharmacy);
  }
  if (has(r'отел|гостиниц|хостел|жиль|ночлег|переночевать|апартамент')) {
    return const SearchIntent(category: PoiCategory.hotel);
  }
  if (has(r'ресторан|кафе|поесть|пообедать|поужинать|обед|ужин|столов|фастфуд|шаурм|пицц|суши|кофейн')) {
    return const SearchIntent(category: PoiCategory.restaurant);
  }
  if (has(r'такси')) {
    return const SearchIntent(category: PoiCategory.taxi);
  }
  if (has(r'больниц|стационар|травмпункт')) {
    return const SearchIntent(category: PoiCategory.hospital);
  }
  if (has(r'клиник|поликлиник|врач|доктор')) {
    return const SearchIntent(category: PoiCategory.clinic);
  }
  if (has(r'зарядк|зарядить|электромобил|ev[-\s]?заряд')) {
    return const SearchIntent(category: PoiCategory.charging);
  }
  if (has(r'метро|подземк')) {
    return const SearchIntent(category: PoiCategory.metro);
  }
  if (has(r'электричк|поезд|вокзал|железнодорож|(^|[^а-я])жд([^а-я]|$)')) {
    return const SearchIntent(category: PoiCategory.railway);
  }
  if (has(r'аэропорт|аэровокзал')) {
    return const SearchIntent(category: PoiCategory.airport);
  }
  if (has(r'трамва')) {
    return const SearchIntent(category: PoiCategory.tram);
  }
  if (has(r'паром|переправ')) {
    return const SearchIntent(category: PoiCategory.ferry);
  }
  if (has(r'камер[аы] хранени|багаж')) {
    return const SearchIntent(category: PoiCategory.luggage);
  }
  if (has(r'салон связи|симк|мтс|билайн|мегафон|теле2')) {
    return const SearchIntent(category: PoiCategory.mobileShop);
  }
  if (has(r'прокат авто|аренда авто|арендовать машин|rent a car')) {
    return const SearchIntent(category: PoiCategory.carRental);
  }
  if (has(r'велосипед|велопрокат|вело')) {
    return const SearchIntent(category: PoiCategory.bikeRental);
  }
  if (has(r'самокат')) {
    return const SearchIntent(category: PoiCategory.scooterRental);
  }

  return SearchIntent(cleaned: _withoutFillers(t));
}

String _withoutFillers(String text) {
  final words = text.split(' ').where((word) => word.isNotEmpty);
  final kept = words.where((word) => !_fillers.contains(word)).toList();
  return kept.isEmpty ? text : kept.join(' ');
}
