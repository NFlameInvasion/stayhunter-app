import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../data/city.dart';
import '../data/poi.dart';
import '../data/poi_repository.dart';
import '../geo/distance.dart';
import '../geo/route.dart';
import '../map/basemap.dart';
import '../search/query_intent.dart';
import '../theme/app_theme.dart';
import 'category_bar.dart';
import 'map_controls.dart';
import 'poi_card.dart';

/// Главный экран: карта на весь экран и панель снизу — поиск, категории, объекты.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _map = MapController();
  final _search = TextEditingController();
  final _repository = const PoiRepository();
  final _speech = stt.SpeechToText();

  City _city = cities.first;
  List<Poi> _all = const [];
  bool _loading = true;
  String? _error;

  /// Что применено к списку: категория и слова. Поле ввода живёт отдельно —
  /// человек набирает текст, а поиск начинается по кнопке.
  PoiCategory? _category;
  String _phrase = '';
  String? _intentNote;

  Poi? _selected;

  /// Где человек: появится после кнопки «Где я».
  LatLng? _me;
  bool _locating = false;

  /// Поворот карты: нужен компасу, чтобы показывать, где север.
  double _rotation = 0;

  /// Построенный пеший маршрут и объект, к которому он ведёт.
  RoutePlan? _route;
  int? _routeFor;
  bool _routing = false;

  /// Голос: распознавание телефона, без отправки звука наружу.
  bool _speechReady = false;
  bool _listening = false;

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
    _speech.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repository.load(_city.asset);
      final from = _me ?? _city.center;
      list.sort((a, b) => metersBetween(from, LatLng(a.lat, a.lon))
          .compareTo(metersBetween(from, LatLng(b.lat, b.lon))));
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

  Future<void> _switchCity(City city) async {
    if (city.key == _city.key) return;
    setState(() {
      _city = city;
      _all = const [];
      _selected = null;
      _route = null;
      _routeFor = null;
      _category = null;
      _phrase = '';
      _intentNote = null;
      _search.clear();
    });
    _map.move(city.center, city.initialZoom);
    await _load();
  }

  Future<void> _pickCity() async {
    final chosen = await showModalBottomSheet<City>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Город', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            for (final city in cities)
              ListTile(
                title: Text(city.name),
                trailing: city.key == _city.key ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, city),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen != null) await _switchCity(chosen);
  }

  /// Что показываем сейчас: категория из разбора фразы и поиск по словам.
  List<Poi> get _visible {
    final query = _phrase.trim().toLowerCase();
    return _all.where((poi) {
      if (_category != null && poi.category != _category) return false;
      if (query.isEmpty) return true;
      return poi.name.toLowerCase().contains(query) ||
          poi.address.toLowerCase().contains(query) ||
          poi.category.label.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  void _select(Poi poi) {
    setState(() {
      _selected = poi;
      _route = null;
      _routeFor = null;
    });
    _map.move(LatLng(poi.lat, poi.lon), 16.4);
  }

  void _closeCard() {
    setState(() {
      _selected = null;
      _route = null;
      _routeFor = null;
    });
  }

  void _showNote(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Кнопка «Найти»: понять фразу и применить к списку.
  void _submitSearch() {
    FocusScope.of(context).unfocus();
    final text = _search.text.trim();
    if (text.isEmpty) {
      setState(() {
        _phrase = '';
        _category = null;
        _intentNote = null;
      });
      return;
    }

    final intent = understandQuery(text);
    setState(() {
      if (intent.understood) {
        _category = intent.category;
        _phrase = '';
        _intentNote = 'Понял: ${intent.category!.label}';
      } else {
        _category = null;
        _phrase = intent.cleaned ?? text.toLowerCase();
        _intentNote = 'Ищу по словам: «$text»';
      }
    });
  }

  void _clearSearch() {
    _search.clear();
    setState(() {
      _phrase = '';
      _category = null;
      _intentNote = null;
    });
  }

  /// Голос: слушаем телефон, заполняем поле и сразу ищем.
  Future<void> _toggleVoice() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') && mounted) {
            setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
    }
    if (!_speechReady) {
      _showNote('Распознавание речи недоступно — проверь микрофон');
      return;
    }

    setState(() => _listening = true);
    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(
        localeId: 'ru_RU',
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
      ),
      onResult: (result) {
        _search.text = result.recognizedWords;
        _search.selection = TextSelection.fromPosition(TextPosition(offset: _search.text.length));
        setState(() {});
        if (result.finalResult) {
          setState(() => _listening = false);
          _submitSearch();
        }
      },
    );
  }

  /// Показать, где мы находимся, и подвести камеру.
  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showNote('Включи геолокацию в телефоне');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showNote('Нет доступа к геолокации');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      final me = LatLng(position.latitude, position.longitude);
      setState(() => _me = me);
      _map.move(me, 16.2);
    } catch (_) {
      _showNote('Не удалось определить место — попробуй на улице');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Пеший маршрут до объекта — по улицам, на нашей карте, без Google.
  Future<void> _buildRoute(Poi poi) async {
    if (_routing) return;
    setState(() => _routing = true);
    final plan = await planWalkingRoute(
      from: _me ?? _map.camera.center,
      to: LatLng(poi.lat, poi.lon),
    );
    if (!mounted) return;
    setState(() {
      _routing = false;
      if (plan != null) {
        _route = plan;
        _routeFor = poi.id;
      }
    });

    if (plan == null) {
      _showNote('Маршрут не построился — попробуй ещё раз');
      return;
    }
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(plan.points),
        padding: const EdgeInsets.fromLTRB(50, 110, 50, 340),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final from = _me ?? _city.center;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _city.center,
              initialZoom: _city.initialZoom,
              minZoom: 3,
              maxZoom: 19,
              onPositionChanged: (camera, _) {
                if ((camera.rotation - _rotation).abs() > 0.3) {
                  setState(() => _rotation = camera.rotation);
                }
              },
              onTap: (_, __) => _closeCard(),
            ),
            children: [
              TileLayer(
                urlTemplate: Basemap.of(widget.isDark).url,
                tileSize: 512,
                zoomOffset: -1,
                userAgentPackageName: 'ru.nflame.stayhunter',
                tileBuilder: (context, tile, _) => ColorFiltered(
                  colorFilter: Basemap.of(widget.isDark).grade,
                  child: tile,
                ),
              ),
              if (_route != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _route!.points,
                      strokeWidth: 5,
                      color: accent,
                    ),
                  ],
                ),
              MarkerLayer(markers: _markers(visible, from)),
            ],
          ),
          Positioned(
            left: 12,
            top: MediaQuery.paddingOf(context).top + 8,
            child: _pill(
              scheme,
              InkWell(
                onTap: _pickCity,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _city.name,
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.expand_more, size: 16, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: MediaQuery.paddingOf(context).top + 8,
            child: Tooltip(
              message: widget.isDark ? 'Светлая тема' : 'Тёмная тема',
              child: Material(
                color: scheme.surface,
                shape: const CircleBorder(),
                elevation: 3,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.onToggleTheme,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(
                      widget.isDark ? Icons.light_mode : Icons.dark_mode,
                      size: 20,
                      color: accent,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: MediaQuery.paddingOf(context).top + 60,
            child: MapControls(
              rotation: _rotation,
              onNorth: () => _map.rotate(0),
              onLocate: _locate,
              locating: _locating,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _panel(visible, from),
          ),
        ],
      ),
    );
  }

  Widget _pill(ColorScheme scheme, Widget child) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12)],
      ),
      child: child,
    );
  }

  List<Marker> _markers(List<Poi> visible, LatLng from) {
    const limit = 400;
    final markers = visible.take(limit).map((poi) {
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
    }).toList();

    final me = _me;
    if (me != null) {
      markers.add(
        Marker(
          point: me,
          width: 26,
          height: 26,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1D4ED8),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 10)],
            ),
          ),
        ),
      );
    }
    return markers;
  }

  Widget _panel(List<Poi> visible, LatLng from) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 24, offset: Offset(0, -6))],
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
                onSubmitted: (_) => _submitSearch(),
                decoration: InputDecoration(
                  hintText: 'Что найти? Банк, обмен, аптека…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: _listening ? 'Остановить' : 'Сказать голосом',
                        icon: Icon(
                          _listening ? Icons.mic : Icons.mic_none,
                          size: 20,
                          color: _listening ? const Color(0xFFB42318) : null,
                        ),
                        onPressed: _toggleVoice,
                      ),
                      IconButton(
                        tooltip: 'Найти',
                        icon: const Icon(Icons.arrow_forward, size: 20),
                        onPressed: _submitSearch,
                      ),
                    ],
                  ),
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
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
                onChanged: (value) => setState(() {
                  _category = value;
                  _intentNote = null;
                }),
              ),
              const SizedBox(height: 8),
              if (_selected != null)
                PoiCard(
                  poi: _selected!,
                  meters: metersBetween(from, LatLng(_selected!.lat, _selected!.lon)),
                  onClose: _closeCard,
                  onRoute: () => _buildRoute(_selected!),
                  routing: _routing,
                  route: _routeFor == _selected!.id ? _route : null,
                )
              else ...[
                if (_intentNote != null) _intentRow(scheme),
                _results(visible, from),
              ],
              const SizedBox(height: 6),
              Text(
                'Данные © OpenStreetMap · карта © CARTO',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _intentRow(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _intentNote!,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          IconButton(
            tooltip: 'Сбросить поиск',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 16),
            onPressed: _clearSearch,
          ),
        ],
      ),
    );
  }

  Widget _results(List<Poi> visible, LatLng from) {
    final scheme = Theme.of(context).colorScheme;
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
          visible.isEmpty ? 'Ничего не найдено' : 'Найдено: ${visible.length}',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 168,
          child: ListView.builder(
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final poi = visible[index];
              final meters = metersBetween(from, LatLng(poi.lat, poi.lon));
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
