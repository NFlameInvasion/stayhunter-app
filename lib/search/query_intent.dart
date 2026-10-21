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
    return const SearchIntent(category: PoiCategory.exchange);
  }
  // «банкет» и «банковский» — не банк: после «банк» не должно идти «ет».
  if (has(r'банк(?!ет)')) {
    return const SearchIntent(category: PoiCategory.bank);
  }
  if (has(r'аптек|лекарств|таблет|медикам|зеленый крест')) {
    return const SearchIntent(category: PoiCategory.pharmacy);
  }
  if (has(r'супермаркет|гипермаркет|универсам')) {
    return const SearchIntent(category: PoiCategory.supermarket);
  }
  if (has(r'магазин|продукт|еда|пить|воды|перекус|купить еды')) {
    return const SearchIntent(category: PoiCategory.shop);
  }
  if (has(r'отел|гостиниц|хостел|жиль|ночлег|переночевать|апартамент')) {
    return const SearchIntent(category: PoiCategory.hotel);
  }

  return SearchIntent(cleaned: _withoutFillers(t));
}

String _withoutFillers(String text) {
  final words = text.split(' ').where((word) => word.isNotEmpty);
  final kept = words.where((word) => !_fillers.contains(word)).toList();
  return kept.isEmpty ? text : kept.join(' ');
}
