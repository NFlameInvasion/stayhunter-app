import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/poi.dart';
import '../geo/bearing.dart';
import '../geo/distance.dart';
import '../geo/route.dart';
import '../theme/app_theme.dart';

/// Карточка выбранного объекта: что это, где, когда открыто, как дойти
/// и куда посмотреть подробнее.
class PoiCard extends StatelessWidget {
  const PoiCard({
    super.key,
    required this.poi,
    required this.meters,
    required this.onClose,
    required this.onRoute,
    required this.routing,
    this.route,
    this.error,
    this.headingDeg,
    this.bearingDeg,
  });

  final Poi poi;
  final double meters;
  final VoidCallback onClose;
  final VoidCallback onRoute;

  /// Идёт построение маршрута — кнопка показывает это и не нажимается дважды.
  final bool routing;

  /// Построенный пеший маршрут; пока его нет, показываем расстояние по прямой.
  final RoutePlan? route;

  /// Почему маршрут не построился: словами, в карточке, а не всплывашкой.
  final String? error;

  /// Куда смотрит телефон и куда находится объект: по ним рисуем стрелку.
  final double? headingDeg;
  final double? bearingDeg;

  Future<void> _openSite() async {
    final uri = poi.website.isNotEmpty
        ? Uri.tryParse(poi.website.contains('://') ? poi.website : 'https://${poi.website}')
        : Uri.parse('https://www.openstreetmap.org/node/${poi.id}');
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = poi.category.color;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(poi.category.icon, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      poi.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [poi.category.label, if (poi.address.isNotEmpty) poi.address].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                    if (poi.hours.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        poi.hours,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF067647)),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Закрыть',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            route != null
                ? '${formatDistance(route!.meters)} · ${(route!.seconds / 60).ceil()} мин пешком'
                : '${formatDistance(meters)} по прямой · ${walkMinutes(meters)} пешком',
            style: TextStyle(fontSize: 13, color: scheme.onSurface),
          ),
          if (headingDeg != null && bearingDeg != null) ...[
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final relative = relativeBearing(bearing: bearingDeg!, heading: headingDeg!);
              return Row(
                children: [
                  Transform.rotate(
                    angle: relative * math.pi / 180,
                    child: const Icon(Icons.navigation, size: 20, color: accent),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${directionWords(relative)} · повернись по стрелке',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              );
            }),
          ],
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(
              error!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFB42318)),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: routing ? null : onRoute,
                  icon: routing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.directions_walk, size: 18),
                  label: Text(routing ? 'Строю…' : 'Маршрут'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _openSite,
                icon: Icon(poi.website.isNotEmpty ? Icons.public : Icons.map_outlined, size: 18),
                label: Text(poi.website.isNotEmpty ? 'Сайт' : 'OpenStreetMap'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
