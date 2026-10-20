import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../audio/device_sound.dart';
import '../data/city.dart';
import '../data/poi.dart';
import '../data/poi_repository.dart';
import '../geo/bearing.dart';
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

  /// Куда смотрит телефон (0 — север). null — компас недоступен или ещё не пришёл.
  double? _heading;
  StreamSubscription<CompassEvent>? _compass;

  /// Построенный пеший маршрут и объект, к которому он ведёт.
  RoutePlan? _route;
  int? _routeFor;
  bool _routing = false;
  String? _routeError;

  /// Ответ на фразу словами: сколько нашлось и три ближайших. Карта показывает
  /// точки, но человеку нужен ещё и ответ — иначе непонятно, что произошло.
  List<Poi> _answerTop = const [];
  int _answerCount = 0;
  bool _answerCollapsed = false;

  /// Голос: распознавание телефона, без отправки звука наружу.
  bool _speechReady = false;
  bool _listening = false;
  String _voiceConfirmed = '';
  String _voiceDraft = '';
  Timer? _voiceLimit;
  Timer? _voiceRestart;
  DateTime? _voiceStarted;

  /// Предел одной голосовой фразы — две минуты, как в Aido.
  static const _voiceMax = Duration(minutes: 2);

  /// Текущий зум: по нему решаем, подписывать ли объекты на карте.
  double _zoom = 14;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() {}));
    try {
      _compass = FlutterCompass.events?.listen(
        (event) {
          final heading = event.heading;
          if (heading != null && mounted) setState(() => _heading = heading);
        },
        onError: (_) {},
      );
    } catch (_) {
      // Телефон без компаса — стрелку направления просто не рисуем.
    }
  }

  @override
  void dispose() {
    _compass?.cancel();
    _voiceLimit?.cancel();
    _voiceRestart?.cancel();
    unmuteDeviceSound();
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
      _routeError = null;
    });
    _map.move(LatLng(poi.lat, poi.lon), 16.4);
  }

  void _closeCard() {
    setState(() {
      _selected = null;
      _route = null;
      _routeFor = null;
      _routeError = null;
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
    _showAnswer(_visible);
  }

  /// Показать ответ: три ближайших и камеру на них.
  void _showAnswer(List<Poi> found) {
    final from = _me ?? _map.camera.center;
    final sorted = [...found]..sort((a, b) => metersBetween(from, LatLng(a.lat, a.lon))
        .compareTo(metersBetween(from, LatLng(b.lat, b.lon))));
    final top = sorted.take(3).toList(growable: false);

    setState(() {
      _answerCount = found.length;
      _answerTop = top;
      _answerCollapsed = false;
    });

    if (top.isEmpty) return;
    if (top.length == 1) {
      _map.move(LatLng(top.first.lat, top.first.lon), 16);
      return;
    }
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(top.map((p) => LatLng(p.lat, p.lon)).toList()),
        padding: const EdgeInsets.fromLTRB(60, 120, 60, 380),
      ),
    );
  }

  void _clearSearch() {
    _search.clear();
    setState(() {
      _phrase = '';
      _category = null;
      _intentNote = null;
      _answerTop = const [];
      _answerCount = 0;
    });
  }

  /// Голос: слушаем телефон, заполняем поле и сразу ищем.
  Future<void> _toggleVoice() async {
    if (_listening) {
      // Второе нажатие — конец фразы. Паузы её не заканчивают.
      await _stopVoice(submit: true);
      return;
    }

    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        onStatus: (status) {
          // Телефон сам заканчивает сеанс на паузе. Пока человек не нажал «стоп»
          // и не вышло две минуты — начинаем слушать снова и копим сказанное.
          if (_listening && (status == 'done' || status == 'notListening')) {
            _scheduleVoiceRestart();
          }
        },
        onError: (_) {
          if (_listening) _scheduleVoiceRestart();
        },
      );
    }
    if (!_speechReady) {
      _showNote('Распознавание речи недоступно — проверь микрофон');
      return;
    }

    _voiceConfirmed = '';
    _voiceDraft = '';
    _voiceStarted = DateTime.now();
    setState(() => _listening = true);
    // Системный писк распознавателя глушим на время записи.
    await muteDeviceSound();
    _voiceLimit?.cancel();
    _voiceLimit = Timer(_voiceMax, () => _stopVoice(submit: true));
    await _startListening();
  }

  /// Один сеанс слушания. Телефон может окончить его сам — тогда начнём новый.
  Future<void> _startListening() async {
    try {
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          localeId: 'ru_RU',
          listenFor: const Duration(minutes: 2),
          pauseFor: const Duration(seconds: 3),
          partialResults: true,
        ),
        onResult: _onVoiceResult,
      );
    } catch (_) {
      await _stopVoice(submit: false);
    }
  }

  void _onVoiceResult(SpeechRecognitionResult result) {
    final text = result.recognizedWords.trim();
    if (text.isEmpty) return;
    if (result.finalResult) {
      _voiceConfirmed = _joinVoice(_voiceConfirmed, text);
      _voiceDraft = '';
    } else {
      _voiceDraft = text;
    }
    final combined = _joinVoice(_voiceConfirmed, _voiceDraft);
    _search.text = combined;
    _search.selection = TextSelection.fromPosition(TextPosition(offset: combined.length));
    setState(() {});
  }

  /// Сложить куски так, чтобы одно и то же не повторялось.
  String _joinVoice(String confirmed, String draft) {
    final first = confirmed.trim();
    final second = draft.trim();
    if (first.isEmpty) return second;
    if (second.isEmpty) return first;
    if (first.endsWith(second)) return first;
    if (second.startsWith(first)) return second;
    return '$first $second';
  }

  /// Продолжить слушать, если человек ещё не закончил и время не вышло.
  void _scheduleVoiceRestart() {
    if (!_listening) return;
    final started = _voiceStarted;
    if (started != null && DateTime.now().difference(started) >= _voiceMax) {
      _stopVoice(submit: true);
      return;
    }
    _voiceRestart?.cancel();
    _voiceRestart = Timer(const Duration(milliseconds: 500), () {
      if (_listening) _startListening();
    });
  }

  Future<void> _stopVoice({required bool submit}) async {
    _voiceLimit?.cancel();
    _voiceRestart?.cancel();
    if (mounted) setState(() => _listening = false);
    try {
      await _speech.stop();
    } catch (_) {
      // Уже не слушает.
    }
    await unmuteDeviceSound();
    final text = _joinVoice(_voiceConfirmed, _voiceDraft);
    if (text.isEmpty) return;
    _search.text = text;
    _search.selection = TextSelection.fromPosition(TextPosition(offset: text.length));
    if (submit) _submitSearch();
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
    setState(() {
      _routing = true;
      _routeError = null;
    });

    RoutePlan? plan;
    try {
      plan = await planWalkingRoute(
        from: _me ?? _map.camera.center,
        to: LatLng(poi.lat, poi.lon),
      );
    } finally {
      if (mounted) {
        setState(() {
          _routing = false;
          if (plan != null) {
            _route = plan;
            _routeFor = poi.id;
          } else {
            _routeError = 'Маршрут не построился. Проверь связь и попробуй ещё раз — '
                'строим по улицам, а не по прямой.';
          }
        });
      }
    }

    if (plan == null || !mounted) return;
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
                var changed = false;
                if ((camera.rotation - _rotation).abs() > 0.3) {
                  _rotation = camera.rotation;
                  changed = true;
                }
                if ((camera.zoom - _zoom).abs() > 0.2) {
                  _zoom = camera.zoom;
                  changed = true;
                }
                if (changed) setState(() {});
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
              onNorth: () {
                // Всегда возвращаем север вверх, даже если карту крутили дважды.
                _map.rotate(0);
                setState(() => _rotation = 0);
              },
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
      final inTop = _answerTop.any((top) => top.id == poi.id);
      final color = poi.category.color;
      return Marker(
        point: LatLng(poi.lat, poi.lon),
        width: isSelected ? 44 : (inTop ? 40 : 34),
        height: isSelected ? 44 : (inTop ? 40 : 34),
        child: GestureDetector(
          onTap: () => _select(poi),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? color : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected || inTop ? color : const Color(0xFFE4E7EC),
                width: isSelected ? 3 : (inTop ? 3 : 2),
              ),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8)],
            ),
            child: Icon(
              poi.category.icon,
              size: isSelected ? 22 : (inTop ? 19 : 17),
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
          width: 54,
          height: 54,
          child: _MeMarker(heading: _heading, mapRotation: _rotation),
        ),
      );
    }

    // Подписи: выбранный объект, три из ответа и — на близком зуме — ближайшие.
    final scheme = Theme.of(context).colorScheme;
    final labelled = <Poi>[];
    void addLabel(Poi poi) {
      if (!labelled.any((x) => x.id == poi.id)) labelled.add(poi);
    }

    final selected = _selected;
    if (selected != null) addLabel(selected);
    for (final poi in _answerTop) {
      addLabel(poi);
    }
    if (_zoom >= 16) {
      for (final poi in visible.take(8)) {
        addLabel(poi);
      }
    }

    for (final poi in labelled) {
      markers.add(
        Marker(
          point: LatLng(poi.lat, poi.lon),
          width: 190,
          height: 30,
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => _select(poi),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6)],
                  ),
                  child: Text(
                    poi.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
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
                // Поле растёт под длинную фразу: до четырёх строк, дальше прокрутка.
                minLines: 1,
                maxLines: 4,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Что найти? Банк, обмен, аптека…',
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.search, size: 20),
                  ),
                  suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: _listening ? 'Остановить' : 'Сказать голосом',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                          icon: Icon(
                            _listening ? Icons.mic : Icons.mic_none,
                            size: 20,
                            color: _listening ? const Color(0xFFB42318) : null,
                          ),
                          onPressed: _toggleVoice,
                        ),
                        IconButton(
                          tooltip: 'Найти',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                          icon: const Icon(Icons.arrow_forward, size: 20),
                          onPressed: _submitSearch,
                        ),
                      ],
                    ),
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
                  _answerTop = const [];
                  _answerCount = 0;
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
                  error: _routeError,
                  headingDeg: _heading,
                  bearingDeg: _me == null
                      ? null
                      : bearingBetween(_me!, LatLng(_selected!.lat, _selected!.lon)),
                )
              else ...[
                if (_intentNote != null) _intentRow(scheme),
                if (_answerTop.isNotEmpty) _answerCard(scheme, from),
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

  /// Ответ на запрос: сколько нашлось и три ближайших, с переходом к каждому.
  Widget _answerCard(ColorScheme scheme, LatLng from) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _answerCollapsed = !_answerCollapsed),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _answerCount == 0
                          ? 'Ничего не нашлось'
                          : 'Нашёл $_answerCount · ближайшие ${_answerTop.length}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(
                    _answerCollapsed ? Icons.expand_more : Icons.expand_less,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (!_answerCollapsed)
            for (var i = 0; i < _answerTop.length; i++)
              InkWell(
                onTap: () => _select(_answerTop[i]),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Text('${i + 1}.', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _answerTop[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${_answerTop[i].category.label} · '
                              '${formatDistance(metersBetween(from, LatLng(_answerTop[i].lat, _answerTop[i].lon)))} '
                              '· ${walkMinutes(metersBetween(from, LatLng(_answerTop[i].lat, _answerTop[i].lon)))} пешком',
                              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
        ],
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
          // Когда сверху уже показан ответ с тремя ближайшими, списку хватает
          // половины места: карта должна оставаться видимой.
          height: _answerTop.isNotEmpty ? 118 : 168,
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

/// Точка «я» со стрелкой направления: поворачивается вместе с телефоном,
/// а не с картой — поэтому из угла вычитается поворот карты.
class _MeMarker extends StatelessWidget {
  const _MeMarker({required this.heading, required this.mapRotation});

  final double? heading;
  final double mapRotation;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF1D4ED8);
    final h = heading;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (h != null)
          Transform.rotate(
            angle: (h - mapRotation) * math.pi / 180,
            child: const SizedBox.expand(
              child: Align(
                alignment: Alignment.topCenter,
                child: Icon(Icons.navigation, size: 22, color: blue),
              ),
            ),
          ),
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 10)],
          ),
        ),
      ],
    );
  }
}
