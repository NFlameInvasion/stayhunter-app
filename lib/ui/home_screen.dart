import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../audio/device_sound.dart';
import '../data/city.dart';
import '../data/poi.dart';
import '../data/poi_repository.dart';
import '../geo/bearing.dart';
import '../geo/distance.dart';
import '../geo/route.dart';
import '../map/vector_style.dart';
import '../search/query_intent.dart';
import '../theme/app_theme.dart';
import 'settings_sheet.dart';
import 'category_bar.dart';
import 'map_controls.dart';
import 'poi_card.dart';

/// Главный экран: векторная карта на весь экран и панель снизу — поиск,
/// категории, ответ и объекты.
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
  final _search = TextEditingController();
  final _repository = const PoiRepository();
  final _speech = stt.SpeechToText();

  ml.MapLibreMapController? _map;

  City _city = cities.first;
  List<Poi> _all = const [];
  bool _loading = true;
  String? _error;

  PoiCategory? _category;
  String _phrase = '';
  String? _intentNote;

  Poi? _selected;

  LatLng? _me;
  bool _locating = false;

  double _rotation = 0;
  double _zoom = 14;

  RoutePlan? _route;
  int? _routeFor;
  bool _routing = false;
  String? _routeError;

  List<Poi> _answerTop = const [];
  int _answerCount = 0;
  bool _answerCollapsed = false;
  bool _panelCollapsed = false;

  double? _heading;
  StreamSubscription<CompassEvent>? _compass;
  double? _drawnHeading;

  bool _speechReady = false;
  bool _listening = false;
  String _voiceConfirmed = '';
  String _voiceDraft = '';
  Timer? _voiceLimit;
  Timer? _voiceRestart;
  DateTime? _voiceStarted;
  static const _voiceMax = Duration(minutes: 2);

  /// Значки на карте: по номеру значка понимаем, по какому объекту тапнули.
  final Map<String, Poi> _symbolPois = {};

  ml.Fill? _meTriangle;
  bool _iconsReady = false;
  bool _triangleBusy = false;
  bool _redrawing = false;
  bool _redrawPending = false;

  /// Если плитки не пришли, показываем причину прямо на карте: без этого
  /// пустое поле не отличить от медленной загрузки.
  String? _tileProblem;

  /// Место, найденное по названию: не объект из списка, а точка на карте.
  LatLng? _landmark;
  String? _landmarkName;

  @override
  void initState() {
    super.initState();
    _load();
    _checkTiles();
    _search.addListener(() => setState(() {}));
    try {
      _compass = FlutterCompass.events?.listen(
        (event) {
          final heading = event.heading;
          if (heading == null || !mounted) return;
          setState(() => _heading = heading);
          _updateTriangle(heading);
        },
        onError: (_) {},
      );
    } catch (_) {
      // Телефон без компаса — стрелку направления просто не рисуем.
    }
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDark != widget.isDark) {
      // Стиль меняется целиком: аннотации после этого рисуются заново.
      _iconsReady = false;
      _map?.setStyle(buildVectorStyle(dark: widget.isDark));
    }
  }

  @override
  void dispose() {
    _compass?.cancel();
    _voiceLimit?.cancel();
    _voiceRestart?.cancel();
    unmuteDeviceSound();
    _search.dispose();
    _speech.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------ данные

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
      await _redraw();
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
      _answerTop = const [];
      _answerCount = 0;
      _search.clear();
    });
    _moveCamera(city.center.latitude, city.center.longitude, city.initialZoom);
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

  // ------------------------------------------------------------------- карта

  void _onMapCreated(ml.MapLibreMapController controller) {
    _map = controller;
    controller.onSymbolTapped.add((symbol) {
      final poi = _symbolPois[symbol.id];
      if (poi != null) _select(poi);
    });
    _redraw();
  }

  Future<void> _onStyleLoaded() async {
    _iconsReady = false;
    await _redraw();
  }

  void _onCameraIdle() {
    final camera = _map?.cameraPosition;
    if (camera == null) return;
    final bearing = camera.bearing;
    final zoom = camera.zoom;
    final zoomChanged = (zoom - _zoom).abs() > 0.05;
    if ((bearing - _rotation).abs() > 0.5 || zoomChanged) {
      setState(() {
        _rotation = bearing;
        _zoom = zoom;
      });
    }
    // При смене масштаба треугольник пересчитываем: его размер задан в метрах.
    if (zoomChanged && _me != null) _updateTriangle(_heading ?? 0, force: true);
  }

  void _moveCamera(double lat, double lon, double zoom) {
    _map?.animateCamera(
      ml.CameraUpdate.newLatLngZoom(ml.LatLng(lat, lon), zoom),
    );
  }

  void _fitPoints(List<LatLng> points) {
    if (points.isEmpty) return;
    var south = points.first.latitude;
    var north = points.first.latitude;
    var west = points.first.longitude;
    var east = points.first.longitude;
    for (final point in points) {
      south = math.min(south, point.latitude);
      north = math.max(north, point.latitude);
      west = math.min(west, point.longitude);
      east = math.max(east, point.longitude);
    }
    if (points.length == 1) {
      _moveCamera(points.first.latitude, points.first.longitude, 16);
      return;
    }
    _map?.animateCamera(
      ml.CameraUpdate.newLatLngBounds(
        ml.LatLngBounds(
          southwest: ml.LatLng(south, west),
          northeast: ml.LatLng(north, east),
        ),
        left: 50,
        top: 120,
        right: 50,
        bottom: 340,
      ),
    );
  }

  Future<void> _redraw() async {
    final controller = _map;
    if (controller == null) return;
    // Один проход за раз: пока идёт отрисовка, камера успевает дёрнуться
    // несколько раз, и повторная очистка съедала только что поставленные значки.
    if (_redrawing) {
      _redrawPending = true;
      return;
    }
    _redrawing = true;
    try {
      await _redrawInner(controller);
    } catch (_) {
      // Сбой отрисовки не должен запирать карту: иначе значки и маршрут
      // перестают появляться до перезапуска приложения.
    } finally {
      _redrawing = false;
      if (_redrawPending) {
        _redrawPending = false;
        await _redraw();
      }
    }
  }

  Future<void> _redrawInner(ml.MapLibreMapController controller) async {

    await controller.clearCircles();
    await controller.clearSymbols();
    await controller.clearLines();
    await controller.clearFills();
    _symbolPois.clear();
    _meTriangle = null;

    if (!_iconsReady) {
      for (final category in PoiCategory.values) {
        try {
          await controller.addImage('ic-${category.key}', await _iconPng(category));
        } catch (_) {
          // Без значка категория останется точкой — не критично.
        }
      }
      _iconsReady = true;
    }

    final visible = _visible;
    // На дальних масштабах близкие объекты налезают друг на друга: оставляем
    // один значок на клетку экрана, а при приближении показываем все.
    final drawn = <Poi>[];
    final cells = <String>{};
    for (final poi in visible) {
      if (_zoom >= 14.5) {
        drawn.add(poi);
      } else {
        final cell = '${(_worldX(poi.lon) / 58).floor()}:'
            '${(_worldY(poi.lat) / 58).floor()}';
        if (cells.add(cell)) drawn.add(poi);
      }
      if (drawn.length >= 400) break;
    }

    for (final poi in drawn) {
      final isSelected = _selected?.id == poi.id;
      try {
        final symbol = await controller.addSymbol(
          ml.SymbolOptions(
            geometry: ml.LatLng(poi.lat, poi.lon),
            iconImage: 'ic-${poi.category.key}',
            iconSize: isSelected ? 0.85 : 0.62,
          ),
        );
        _symbolPois[symbol.id] = poi;
      } catch (_) {
        break;
      }
    }

    for (final poi in _labelled(visible)) {
      try {
        await controller.addSymbol(
          ml.SymbolOptions(
            geometry: ml.LatLng(poi.lat, poi.lon),
            textField: poi.name,
            textSize: 11,
            textColor: widget.isDark ? '#e6edf7' : '#101828',
            textHaloColor: widget.isDark ? '#0b0f14' : '#ffffff',
            textHaloWidth: 1.2,
            textOffset: const Offset(0, 1.3),
            textAnchor: 'top',
          ),
        );
      } catch (_) {
        break;
      }
    }

    final landmark = _landmark;
    if (landmark != null) {
      try {
        await controller.addCircle(
          ml.CircleOptions(
            geometry: ml.LatLng(landmark.latitude, landmark.longitude),
            circleRadius: 9,
            circleColor: '#B42318',
            circleStrokeColor: '#ffffff',
            circleStrokeWidth: 3,
          ),
        );
        await controller.addSymbol(
          ml.SymbolOptions(
            geometry: ml.LatLng(landmark.latitude, landmark.longitude),
            textField: _landmarkName ?? 'Место',
            textSize: 12,
            textColor: widget.isDark ? '#e6edf7' : '#101828',
            textHaloColor: widget.isDark ? '#0b0f14' : '#ffffff',
            textHaloWidth: 1.4,
            textOffset: const Offset(0, 1.6),
            textAnchor: 'top',
          ),
        );
      } catch (_) {
        // Точка появится при следующей перерисовке.
      }
    }

    if (_route != null) {
      try {
        await controller.addLine(
          ml.LineOptions(
            geometry: _route!.points
                .map((p) => ml.LatLng(p.latitude, p.longitude))
                .toList(growable: false),
            lineColor: '#0f7b6c',
            lineWidth: 5,
          ),
        );
      } catch (_) {
        // Маршрут нарисуется при следующей перерисовке.
      }
    }

    final me = _me;
    if (me != null) {
      await controller.addCircle(
        ml.CircleOptions(
          geometry: ml.LatLng(me.latitude, me.longitude),
          circleRadius: 7,
          circleColor: '#1d4ed8',
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 3,
        ),
      );
      try {
        final heading = _heading ?? 0;
        _meTriangle = await controller.addFill(
          ml.FillOptions(
            geometry: [_trianglePoints(me, heading)
                .map((point) => ml.LatLng(point.latitude, point.longitude))
                .toList()],
            fillColor: '#1d4ed8',
            fillOutlineColor: '#ffffff',
            fillOpacity: 0.95,
          ),
        );
        _drawnHeading = heading;
      } catch (_) {
        // Треугольник появится при следующей перерисовке.
      }
    }

  }

  /// Кого подписываем: выбранный, три из ответа и ближайшие на крупном зуме.
  List<Poi> _labelled(List<Poi> visible) {
    final labelled = <Poi>[];
    void add(Poi poi) {
      if (!labelled.any((x) => x.id == poi.id)) labelled.add(poi);
    }

    final selected = _selected;
    if (selected != null) add(selected);
    for (final poi in _answerTop) {
      add(poi);
    }
    if (_zoom >= 16) {
      for (final poi in visible.take(8)) {
        add(poi);
      }
    }
    return labelled;
  }

  double _worldX(double lon) =>
      (lon + 180) / 360 * 256 * math.pow(2, _zoom).toDouble();

  double _worldY(double lat) {
    final s = math.sin(lat * math.pi / 180);
    return (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) *
        256 *
        math.pow(2, _zoom).toDouble();
  }

  /// Треугольник направления: три точки вокруг своего места, повёрнутые
  /// по компасу. Рисунок целиком в наших руках, поэтому его видно всегда.
  List<LatLng> _trianglePoints(LatLng me, double heading) {
    // Длина в метрах считается от масштаба: на экране треугольник всегда
    // около 40 точек, иначе на крупном зуме он закрывает полкарты.
    // Масштаб берём у самой карты: поле _zoom обновляется только по событию
    // остановки камеры и успевает отстать от того, что видно на экране.
    final zoom = _map?.cameraPosition?.zoom ?? _zoom;
    final metersPerPixel = 156543.03392 *
        math.cos(me.latitude * math.pi / 180) /
        math.pow(2, zoom).toDouble();
    final length = (metersPerPixel * 44).clamp(2.0, 1500.0);
    return [
      _destination(me, heading, length),
      _destination(me, heading - 148, length * 0.62),
      _destination(me, heading + 148, length * 0.62),
    ];
  }

  LatLng _destination(LatLng from, double bearingDeg, double meters) {
    const earthRadius = 6378137.0;
    final bearing = bearingDeg * math.pi / 180;
    final lat1 = from.latitude * math.pi / 180;
    final lon1 = from.longitude * math.pi / 180;
    final angular = meters / earthRadius;

    final lat2 = math.asin(math.sin(lat1) * math.cos(angular) +
        math.cos(lat1) * math.sin(angular) * math.cos(bearing));
    final lon2 = lon1 +
        math.atan2(
          math.sin(bearing) * math.sin(angular) * math.cos(lat1),
          math.cos(angular) - math.sin(lat1) * math.sin(lat2),
        );
    return LatLng(lat2 * 180 / math.pi, lon2 * 180 / math.pi);
  }

  Future<void> _updateTriangle(double heading, {bool force = false}) async {
    final drawn = _drawnHeading;
    if (!force && (drawn == null || (heading - drawn).abs() < 6)) return;
    final me = _me;
    final controller = _map;
    if (me == null || controller == null || _triangleBusy) return;

    _triangleBusy = true;
    _drawnHeading = heading;
    try {
      final old = _meTriangle;
      if (old != null) await controller.removeFill(old);
      _meTriangle = await controller.addFill(
        ml.FillOptions(
          geometry: [_trianglePoints(me, heading)
                .map((point) => ml.LatLng(point.latitude, point.longitude))
                .toList()],
          fillColor: '#1d4ed8',
          fillOutlineColor: '#ffffff',
          fillOpacity: 0.95,
        ),
      );
    } catch (_) {
      // Перерисуется в следующем обновлении компаса.
    } finally {
      _triangleBusy = false;
    }
  }

  /// Значок категории в PNG: цветной круг с белой иконкой, как было раньше.
  Future<Uint8List> _iconPng(PoiCategory category) async {
    const size = 96.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));

    canvas.drawCircle(const Offset(48, 48), 39, Paint()..color = category.color);
    canvas.drawCircle(
      const Offset(48, 48),
      39,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8,
    );

    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(category.icon.codePoint),
        style: TextStyle(
          fontFamily: category.icon.fontFamily,
          package: category.icon.fontPackage,
          fontSize: 44,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset((size - painter.width) / 2, (size - painter.height) / 2),
    );

    final image = await recorder.endRecording().toImage(96, 96);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  // ------------------------------------------------------------------ поиск

  void _select(Poi poi) {
    setState(() {
      _selected = poi;
      _route = null;
      _routeFor = null;
      _routeError = null;
      _panelCollapsed = false;
    });
    _moveCamera(poi.lat, poi.lon, 16.4);
    _redraw();
  }

  void _closeCard() {
    setState(() {
      _selected = null;
      _route = null;
      _routeFor = null;
      _routeError = null;
    });
    _redraw();
  }

  void _showNote(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _submitSearch() {
    FocusScope.of(context).unfocus();
    final text = _search.text.trim();
    if (text.isEmpty) {
      setState(() {
        _phrase = '';
        _category = null;
        _intentNote = null;
        _answerTop = const [];
        _answerCount = 0;
      });
      _redraw();
      return;
    }

    final intent = understandQuery(text);
    setState(() {
      _panelCollapsed = false;
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
    // Среди объектов такого может не быть — тогда ищем место по названию.
    if (_visible.isEmpty && text.length > 2) _geocode(text);
  }

  /// Поиск места по названию (Красная площадь, аэропорт): свои данные
  /// знают только объекты, а название улицы или площади — нет.
  Future<void> _geocode(String query) async {
    final uri = Uri.parse(
      'https://tiles.83.220.175.52.nip.io/geocode/search'
      '?q=${Uri.encodeQueryComponent(query)}'
      '&format=json&limit=1&accept-language=ru',
    );
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return;
      final list = jsonDecode(response.body) as List<dynamic>;
      if (list.isEmpty) return;
      final first = list.first as Map<String, dynamic>;
      final lat = double.tryParse('${first['lat']}');
      final lon = double.tryParse('${first['lon']}');
      if (lat == null || lon == null || !mounted) return;
      final name = '${first['display_name']}'.split(',').first.trim();
      setState(() {
        _landmark = LatLng(lat, lon);
        _landmarkName = name;
        _intentNote = 'Нашёл на карте: $name';
        _answerTop = const [];
        _answerCount = 0;
      });
      _moveCamera(lat, lon, 16.5);
      await _redraw();
    } catch (_) {
      // Не нашли — останется «Ничего не найдено», это честно.
    }
  }

  void _showAnswer(List<Poi> found) {
    final from = _me ?? _city.center;
    final sorted = [...found]..sort((a, b) => metersBetween(from, LatLng(a.lat, a.lon))
        .compareTo(metersBetween(from, LatLng(b.lat, b.lon))));
    final top = sorted.take(3).toList(growable: false);

    setState(() {
      _answerCount = found.length;
      _answerTop = top;
      _answerCollapsed = false;
    });

    if (top.isNotEmpty) {
      _fitPoints(top.map((p) => LatLng(p.lat, p.lon)).toList());
    }
    _redraw();
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
    _redraw();
  }

  // ------------------------------------------------------------------ голос

  Future<void> _toggleVoice() async {
    if (_listening) {
      await _stopVoice(submit: true);
      return;
    }

    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        onStatus: (status) {
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
    await muteDeviceSound();
    _voiceLimit?.cancel();
    _voiceLimit = Timer(_voiceMax, () => _stopVoice(submit: true));
    await _startListening();
  }

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

  String _joinVoice(String confirmed, String draft) {
    final first = confirmed.trim();
    final second = draft.trim();
    if (first.isEmpty) return second;
    if (second.isEmpty) return first;
    if (first.endsWith(second)) return first;
    if (second.startsWith(first)) return second;
    return '$first $second';
  }

  void _scheduleVoiceRestart() {
    if (!_listening) return;
    // Телефон закончил сеанс на паузе, не отдав итог: сохраняем то, что он
    // успел расслышать, иначе следующий сеанс начнёт с чистого листа и
    // потеряет всё сказанное до паузы.
    _voiceConfirmed = _joinVoice(_voiceConfirmed, _voiceDraft);
    _voiceDraft = '';
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

  // ------------------------------------------------------------- место и путь

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

      // Сначала точное место, но не ждём его дольше 12 секунд: в помещении
      // спутники не отвечают, и человек должен увидеть хотя бы прошлую точку.
      LatLng? me;
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 12),
          ),
        );
        me = LatLng(position.latitude, position.longitude);
      } catch (_) {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) me = LatLng(last.latitude, last.longitude);
      }
      if (me == null) {
        _showNote('Место не определено: включи GPS и выйди на открытое место');
        return;
      }
      if (!mounted) return;
      setState(() => _me = me!);
      _moveCamera(me.latitude, me.longitude, 16.2);
      await _redraw();
    } catch (_) {
      _showNote('Не удалось определить место — попробуй на улице');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _buildRoute(Poi poi) async {
    if (_routing) return;
    setState(() {
      _routing = true;
      _routeError = null;
    });

    RoutePlan? plan;
    try {
      plan = await planWalkingRoute(
        from: _me ?? _city.center,
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
    _fitPoints(plan.points);
    await _redraw();
  }

  // ------------------------------------------------------------------- вид

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final from = _me ?? _city.center;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          ml.MapLibreMap(
            styleString: buildVectorStyle(dark: widget.isDark),
            initialCameraPosition: ml.CameraPosition(
              target: ml.LatLng(_city.center.latitude, _city.center.longitude),
              zoom: _city.initialZoom,
            ),
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            onCameraIdle: _onCameraIdle,
            trackCameraPosition: true,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: false,
            // Встроенный компас мигал поверх карты; север показывает наша кнопка.
            compassEnabled: false,
            onMapClick: (_, __) => _closeCard(),
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
          if (_tileProblem != null)
            Positioned(
              left: 12,
              right: 64,
              top: MediaQuery.paddingOf(context).top + 50,
              child: GestureDetector(
                onTap: _checkTiles,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB42318),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_tileProblem ?? ''} · нажми, чтобы проверить снова',
                    maxLines: 3,
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 12,
            top: MediaQuery.paddingOf(context).top + 56,
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
            top: MediaQuery.paddingOf(context).top + 8,
            child: Tooltip(
              message: 'Настройки',
              child: Material(
                color: scheme.surface,
                shape: const CircleBorder(),
                elevation: 3,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _openSettings,
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(Icons.settings, size: 20),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: MediaQuery.paddingOf(context).top + 108,
            child: MapControls(
              rotation: _rotation,
              onNorth: () {
                _map?.animateCamera(ml.CameraUpdate.bearingTo(0));
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
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _panelHandle(scheme),
              TextField(
                controller: _search,
                minLines: 1,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Что найти?',
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 2),
                    child: Icon(Icons.search, size: 19),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: _listening ? 'Остановить' : 'Сказать голосом',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(width: 28, height: 32),
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: Icon(
                            _listening ? Icons.mic : Icons.mic_none,
                            size: 18,
                            color: _listening ? const Color(0xFFB42318) : null,
                          ),
                          onPressed: _toggleVoice,
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Найти',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(width: 30, height: 32),
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(Icons.arrow_forward, size: 19),
                          onPressed: _submitSearch,
                        ),
                      ],
                    ),
                  ),
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (!_panelCollapsed) ...[
                const SizedBox(height: 6),
                if (_selected == null)
                CategoryBar(
                  selected: _category,
                  onChanged: (value) {
                    setState(() {
                      _category = value;
                      _intentNote = null;
                      _answerTop = const [];
                      _answerCount = 0;
                    });
                    _redraw();
                  },
                ),
                const SizedBox(height: 6),
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
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _checkTiles() async {
    const url =
        'https://tiles.83.220.175.52.nip.io/planet/20261018_080001_pt/10/618/327.pbf';
    if (mounted) setState(() => _tileProblem = null);
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 12);
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 12));
      final response = await request.close().timeout(const Duration(seconds: 12));
      var received = 0;
      await for (final chunk in response) {
        received += chunk.length;
      }
      client.close();
      if (!mounted) return;
      setState(() {
        _tileProblem = response.statusCode == 200 && received > 0
            ? null
            : 'плитки: ответ ${response.statusCode}, $received б';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _tileProblem = 'плитки: $error');
    }
  }

  Future<void> _openSettings() async {
    await showSettingsSheet(
      context,
      isDark: widget.isDark,
      onToggleTheme: widget.onToggleTheme,
    );
  }

  void _togglePanel() => setState(() => _panelCollapsed = !_panelCollapsed);

  Widget _panelHandle(ColorScheme scheme) {
    var drag = 0.0;
    return GestureDetector(
      // Тянуть можно в любую сторону: вверх — развернуть, вниз — свернуть.
      onVerticalDragStart: (_) => drag = 0,
      onVerticalDragUpdate: (details) => drag += details.delta.dy,
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        final goUp = drag < -14 || velocity < -120;
        final goDown = drag > 14 || velocity > 120;
        if (goUp && _panelCollapsed) _togglePanel();
        if (goDown && !_panelCollapsed) _togglePanel();
      },
      child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _togglePanel,
        child: SizedBox(
          height: 22,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

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
          height: _answerTop.isNotEmpty ? 78 : 100,
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
