import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../data/city.dart';

/// Выбор места поиска: строка ввода (страна, город или «страна, город») плюс
/// подсказки из каталога базы.
///
/// Каталог знает по одному городу на страну, поэтому одного списка мало: люди
/// ищут Мюнхен, Киото, Нюрнберг. Ввод уходит в геокодер, его ответ становится
/// областью поиска объектов — ровно так же, как выбор города из каталога.
class CityPicker extends StatefulWidget {
  const CityPicker({
    super.key,
    required this.cities,
    required this.current,
    this.fullScreen = false,
  });

  final List<City> cities;
  final City current;

  /// Полноэкранный режим: свой AppBar и заголовок, поле ввода прижато к верху.
  final bool fullScreen;

  @override
  State<CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends State<CityPicker> {
  // Свой прокси: он же переводит запрос, если по-русски место не находится.
  static const _geocodeUrl = 'https://map.83.220.175.52.nip.io/api/place';

  String query = '';
  List<City> places = const [];
  bool searching = false;
  Timer? _debounce;
  int _request = 0;

  List<City> get matched {
    final text = query.trim().toLowerCase();
    if (text.isEmpty) return widget.cities;
    return widget.cities
        .where((city) =>
            city.name.toLowerCase().contains(text) ||
            city.country.toLowerCase().contains(text))
        .toList(growable: false);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => query = value);
    _debounce?.cancel();
    final text = value.trim();
    if (text.length < 2) {
      setState(() {
        places = const [];
        searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _searchPlaces(text));
  }

  /// «Мюнхен», «Германия», «Германия, Нюрнберг» — геокодер понимает строку как
  /// место и возвращает рамку; по ней дальше ищутся объекты в базе.
  Future<void> _searchPlaces(String text) async {
    final ticket = ++_request;
    setState(() => searching = true);
    try {
      final uri = Uri.parse(_geocodeUrl).replace(queryParameters: {
        'q': text,
        'lang': 'ru',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200 || !mounted || ticket != _request) {
        return;
      }
      final rows = jsonDecode(response.body) as List<dynamic>;
      final found = <City>[];
      for (final row in rows) {
        final hit = row as Map<String, dynamic>;
        final lat = double.tryParse('${hit['lat']}');
        final lon = double.tryParse('${hit['lon']}');
        final box = (hit['boundingbox'] as List<dynamic>? ?? const <dynamic>[])
            .map((value) => double.tryParse('$value'))
            .toList(growable: false);
        if (lat == null || lon == null || box.length != 4) {
          continue;
        }
        // Nominatim отдаёт рамку как [юг, север, запад, восток].
        final south = box[0]!;
        final north = box[1]!;
        final west = box[2]!;
        final east = box[3]!;
        final display = '${hit['display_name'] ?? ''}';
        final head = display.split(',').first.trim();
        final address = hit['address'] as Map<String, dynamic>? ?? const <String, dynamic>{};
        final country = '${address['country'] ?? ''}'.trim();
        found.add(City.fromPlace(
          name: head.isEmpty ? text : head,
          country: country,
          center: LatLng(lat, lon),
          bbox: CityBbox(south: south, west: west, north: north, east: east),
        ));
      }
      if (!mounted || ticket != _request) {
        return;
      }
      setState(() {
        places = found;
        searching = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _body(context);
    if (!widget.fullScreen) {
      return body;
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Где искать'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Закрыть',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: body,
    );
  }

  Widget _body(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final found = matched;

    // Страны в том порядке, в каком они встретились в списке городов.
    final byCountry = <String, List<City>>{};
    for (final city in found) {
      byCountry.putIfAbsent(city.country, () => []).add(city);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.fullScreen) ...[
              const Text(
                'Где искать',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
              onSubmitted: (value) {
                if (places.isNotEmpty) {
                  Navigator.pop(context, places.first);
                }
              },
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Город, страна или «страна, город»',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: (found.isEmpty && places.isEmpty && !searching)
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('Ничего не нашлось'),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        if (places.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                            child: Text(
                              'Найдено по названию',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          for (final place in places)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.place_outlined, size: 20),
                              title: Text(place.name),
                              subtitle: place.country.isEmpty ? null : Text(place.country),
                              onTap: () => Navigator.pop(context, place),
                            ),
                        ],
                        for (final entry in byCountry.entries) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          for (final city in entry.value)
                            ListTile(
                              dense: true,
                              title: Text(city.name),
                              trailing: city.key == widget.current.key
                                  ? const Icon(Icons.check)
                                  : null,
                              onTap: () => Navigator.pop(context, city),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
