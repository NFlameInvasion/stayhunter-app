import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/poi.dart';
import '../data/poi_repository.dart';
import '../geo/distance.dart';
import 'category_bar.dart';
import 'poi_card.dart';

/// Главный экран: карта на весь экран и панель снизу — поиск, категории, объекты.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _cityCenter = LatLng(41.0082, 28.9744);
  static const _cityName = 'Стамбул · Султанахмет';

  final _map = MapController();
  final _search = TextEditingController();
  final _repository = const PoiRepository();

  List<Poi> _all = const [];
  bool _loading = true;
  String? _error;

  PoiCategory? _category;
  Poi? _selected;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _repository.load();
      list.sort((a, b) => metersBetween(_cityCenter, LatLng(a.lat, a.lon))
          .compareTo(metersBetween(_cityCenter, LatLng(b.lat, b.lon))));
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось прочитать объекты: $error';
        _loading = false;
      });
    }
  }

  /// Что показываем сейчас: фильтр по категории и поиск по названию и адресу.
  List<Poi> get _visible {
    final query = _search.text.trim().toLowerCase();
    return _all.where((poi) {
      if (_category != null && poi.category != _category) return false;
      if (query.isEmpty) return true;
      return poi.name.toLowerCase().contains(query) ||
          poi.address.toLowerCase().contains(query) ||
          poi.category.label.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  void _select(Poi poi) {
    setState(() => _selected = poi);
    _map.move(LatLng(poi.lat, poi.lon), 16.4);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _cityCenter,
              initialZoom: 14.6,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ru.nflame.stayhunter',
              ),
              MarkerLayer(markers: _markers(visible)),
            ],
          ),
          Positioned(
            left: 12,
            top: MediaQuery.paddingOf(context).top + 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12)],
              ),
              child: const Text(
                _cityName,
                style: TextStyle(fontSize: 12, color: Color(0xFF475467)),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _panel(visible),
          ),
        ],
      ),
    );
  }

  List<Marker> _markers(List<Poi> visible) {
    const limit = 400;
    return visible.take(limit).map((poi) {
      final isSelected = _selected?.id == poi.id;
      final color = poi.category.color;
      return Marker(
        point: LatLng(poi.lat, poi.lon),
        width: isSelected ? 44 : 34,
        height: isSelected ? 44 : 34,
        child: GestureDetector(
          onTap: () => _select(poi),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? color : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: isSelected ? color : const Color(0xFFE4E7EC), width: isSelected ? 3 : 2),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8)],
            ),
            child: Icon(
              poi.category.icon,
              size: isSelected ? 22 : 17,
              color: isSelected ? Colors.white : color,
            ),
          ),
        ),
      );
    }).toList(growable: false);
  }

  Widget _panel(List<Poi> visible) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 24, offset: Offset(0, -6))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Что найти? Банк, обмен, аптека…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: IconButton(
                    tooltip: 'Сказать голосом',
                    icon: const Icon(Icons.mic_none, size: 20),
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Голос появится в следующем шаге')),
                    ),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF2F4F7),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              CategoryBar(
                selected: _category,
                onChanged: (value) => setState(() => _category = value),
              ),
              const SizedBox(height: 8),
              if (_selected != null)
                PoiCard(
                  poi: _selected!,
                  meters: metersBetween(_cityCenter, LatLng(_selected!.lat, _selected!.lon)),
                  onClose: () => setState(() => _selected = null),
                )
              else
                _results(visible),
              const SizedBox(height: 6),
              const Text(
                'Данные © OpenStreetMap',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: Color(0xFF98A2B3)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _results(List<Poi> visible) {
    if (_loading) {
      return const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text(_error!, style: const TextStyle(color: Color(0xFFB42318))),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          visible.isEmpty ? 'Ничего не найдено' : 'Рядом: ${visible.length}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 168,
          child: ListView.builder(
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final poi = visible[index];
              final meters = metersBetween(_cityCenter, LatLng(poi.lat, poi.lon));
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: poi.category.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(poi.category.icon, size: 19, color: poi.category.color),
                ),
                title: Text(
                  poi.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${poi.category.label} · ${formatDistance(meters)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => _select(poi),
              );
            },
          ),
        ),
      ],
    );
  }
}
