import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../data/city.dart';

/// Выбор места поиска: одно поле и плоский список городов.
///
/// Каталог знает по одному городу на страну, поэтому список не главный: ввод
/// уходит в геокодер (`/api/place`), тот отдаёт рамку места, и по ней ищутся
/// объекты в базе. Пока ничего не введено — списка нет вообще, только поле:
/// простыня из 49 стран на весь экран только мешает.
class CityPicker extends StatefulWidget {
  const CityPicker({
    super.key,
    required this.cities,
    required this.current,
    this.fullScreen = false,
  });

  final List<City> cities;
  final City current;

  /// Полноэкранный режим: свой AppBar, поле прижато к верху.
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
        final display = '${hit['display_name'] ?? ''}';
        final head = display.split(',').first.trim();
        final address = hit['address'] as Map<String, dynamic>? ?? const <String, dynamic>{};
        final country = '${address['country'] ?? ''}'.trim();
        found.add(City.fromPlace(
          name: head.isEmpty ? text : head,
          country: country,
          center: LatLng(lat, lon),
          bbox: CityBbox(south: box[0]!, west: box[2]!, north: box[1]!, east: box[3]!),
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

  /// Плоский список: найденное геокодером плюс совпадения из каталога, без
  /// группировки по странам. Дубликаты («Москва» из двух источников) схлопываются.
  List<City> _results() {
    final text = query.trim().toLowerCase();
    if (text.isEmpty) {
      return const [];
    }

    final merged = <City>[];
    final seen = <String>{};
    final fromCatalog = widget.cities.where((city) =>
        city.name.toLowerCase().contains(text) || city.country.toLowerCase().contains(text));

    for (final city in [...places, ...fromCatalog]) {
      final key = '${city.name}|${city.country}'.toLowerCase();
      if (seen.add(key)) {
        merged.add(city);
      }
    }
    return merged;
  }

  Widget _row(BuildContext context, City city, ColorScheme scheme) {
    final isCurrent = city.key.isNotEmpty && city.key == widget.current.key;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        city.bbox == null ? Icons.location_city : Icons.place_outlined,
        size: 20,
        color: scheme.onSurfaceVariant,
      ),
      title: Text(city.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: city.country.isEmpty
          ? null
          : Text(city.country, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: isCurrent ? const Icon(Icons.check) : null,
      onTap: () => Navigator.pop(context, city),
    );
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
    final text = query.trim();
    final rows = _results();
    // Список занимает меньше половины экрана: остальное — карта за ним.
    final listHeight = MediaQuery.of(context).size.height * 0.45;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
              onSubmitted: (_) {
                if (rows.isNotEmpty) {
                  Navigator.pop(context, rows.first);
                }
              },
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Город или страна',
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
            if (text.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 28, left: 8, right: 8),
                child: Text(
                  'Введи город или страну. Можно вместе: «Германия, Нюрнберг».',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              )
            else if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Center(
                  child: searching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Ничего не нашлось'),
                ),
              )
            else ...[
              const SizedBox(height: 8),
              SizedBox(
                height: listHeight,
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: rows.length,
                  itemBuilder: (context, index) => _row(context, rows[index], scheme),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
