import 'dart:convert';

/// Палитра игровых вариантов StayHunter — те же цвета, что были в
/// `gamedark.js` и `gamelight.js` на серверной карте.
class MapPalette {
  const MapPalette({
    required this.earth,
    required this.water,
    required this.landuse,
    required this.building,
    required this.road,
    required this.roadCasing,
    required this.label,
    required this.labelHalo,
  });

  final String earth;
  final String water;
  final String landuse;
  final String building;
  final String road;
  final String roadCasing;
  final String label;
  final String labelHalo;

  static const light = MapPalette(
    earth: '#f6f3ee',
    water: '#a8cdea',
    landuse: '#e6ecdf',
    building: '#e3ddd6',
    road: '#ffffff',
    roadCasing: '#d5cec6',
    label: '#2a2a2a',
    labelHalo: '#ffffff',
  );

  static const dark = MapPalette(
    earth: '#12181f',
    water: '#0a2233',
    landuse: '#151f27',
    building: '#1b2530',
    road: '#2a3644',
    roadCasing: '#0d1218',
    label: '#cfe3f5',
    labelHalo: '#06090d',
  );
}

/// Стиль карты: глобальная векторная подложка OpenFreeMap (схема OpenMapTiles)
/// в палитре StayHunter. Подписи — только города и посёлки: улицы и POI
/// подписываем сами, чтобы карта не спорила с объектами.
String buildVectorStyle({required bool dark}) {
  final p = dark ? MapPalette.dark : MapPalette.light;

  final majorRoads = [
    'in',
    'class',
    'motorway',
    'trunk',
    'primary',
    'secondary',
    'tertiary',
  ];
  final minorRoads = ['in', 'class', 'minor', 'service'];

  final style = <String, dynamic>{
    'version': 8,
    'name': dark ? 'StayHunter Night' : 'StayHunter Day',
    'glyphs': 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
    'sources': {
      'openmaptiles': {
        'type': 'vector',
        'url': 'https://tiles.openfreemap.org/planet',
      },
    },
    'layers': <Map<String, dynamic>>[
      {
        'id': 'background',
        'type': 'background',
        'paint': {'background-color': p.earth},
      },
      {
        'id': 'water',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'water',
        'paint': {'fill-color': p.water},
      },
      {
        'id': 'landuse',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'landuse',
        'paint': {'fill-color': p.landuse},
      },
      {
        'id': 'landcover',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'landcover',
        'paint': {'fill-color': p.landuse},
      },
      {
        'id': 'building',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'building',
        'minzoom': 13,
        'paint': {'fill-color': p.building},
      },
      {
        'id': 'road-casing',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'transportation',
        'minzoom': 7,
        'filter': majorRoads,
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': p.roadCasing,
          'line-width': [
            'interpolate', ['linear'], ['zoom'],
            7, 1.4,
            12, 3.2,
            18, 12.0,
          ],
        },
      },
      {
        'id': 'road-major',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'transportation',
        'minzoom': 7,
        'filter': majorRoads,
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': p.road,
          'line-width': [
            'interpolate', ['linear'], ['zoom'],
            7, 0.6,
            12, 2.0,
            18, 9.0,
          ],
        },
      },
      {
        'id': 'road-minor',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'transportation',
        'minzoom': 12,
        'filter': minorRoads,
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': p.road,
          'line-width': [
            'interpolate', ['linear'], ['zoom'],
            12, 0.6,
            16, 2.0,
            18, 4.0,
          ],
        },
      },
      {
        'id': 'place-labels',
        'type': 'symbol',
        'source': 'openmaptiles',
        'source-layer': 'place',
        'minzoom': 5,
        'filter': [
          'in',
          'class',
          'city',
          'town',
        ],
        'layout': {
          'text-field': ['get', 'name'],
          'text-font': ['Noto Sans Regular'],
          'text-size': [
            'interpolate', ['linear'], ['zoom'],
            5, 11,
            10, 13,
            14, 15,
          ],
          'text-allow-overlap': false,
        },
        'paint': {
          'text-color': p.label,
          'text-halo-color': p.labelHalo,
          'text-halo-width': 1.2,
        },
      },
    ],
  };

  return jsonEncode(style);
}
