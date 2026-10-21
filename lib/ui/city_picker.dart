import 'package:flutter/material.dart';

import '../data/city.dart';

/// Выбор города: сначала страны, внутри — города, сверху поиск.
/// При сотнях городов список не листают, а ищут по названию.
class CityPicker extends StatefulWidget {
  const CityPicker({super.key, required this.cities, required this.current});

  final List<City> cities;
  final City current;

  @override
  State<CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends State<CityPicker> {
  String query = '';

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
  Widget build(BuildContext context) {
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
            const Text(
              'Страна и город',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            TextField(
              autofocus: false,
              onChanged: (value) => setState(() => query = value),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Найти город или страну',
                prefixIcon: const Icon(Icons.search, size: 20),
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
              child: found.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('Ничего не нашлось'),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
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
