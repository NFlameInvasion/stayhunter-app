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

/// Понять фразу так, как её говорит человек на улице.
///
/// Порядок проверок важен: «банкомат» содержит «банк», а «обмен валюты в банке» —
/// два слова сразу. Поэтому более узкие понятия проверяются раньше широких.
SearchIntent understandQuery(String text) {
  final t = text.toLowerCase().replaceAll('ё', 'е').trim();
  if (t.isEmpty) return const SearchIntent();

  bool has(String pattern) => RegExp(pattern).hasMatch(t);

  if (has(r'банкомат|банкомат[а-я]*|\bатм\b|снять наличн|наличн')) {
    return const SearchIntent(category: PoiCategory.atm);
  }
  if (has(r'обмен|обменник|валют|менял|менять деньг|курс')) {
    return const SearchIntent(category: PoiCategory.exchange);
  }
  if (has(r'\bбанк')) {
    return const SearchIntent(category: PoiCategory.bank);
  }
  if (has(r'аптек|лекарств|таблет|медикам|зеленый крест')) {
    return const SearchIntent(category: PoiCategory.pharmacy);
  }
  if (has(r'супермаркет|гипермаркет')) {
    return const SearchIntent(category: PoiCategory.supermarket);
  }
  if (has(r'магазин|продукт|еда|пить|воды|перекус')) {
    return const SearchIntent(category: PoiCategory.shop);
  }
  if (has(r'отел|гостиниц|хостел|жиль|ночлег|переночевать')) {
    return const SearchIntent(category: PoiCategory.hotel);
  }

  return SearchIntent(cleaned: t);
}
