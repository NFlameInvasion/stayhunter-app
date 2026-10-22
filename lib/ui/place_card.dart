import 'package:flutter/material.dart';

import '../geo/distance.dart';
import '../geo/route.dart';

/// Карточка найденного МЕСТА (площадь, улица, аэропорт).
///
/// Объекты из нашей базы — это точки обслуживания (банк, аптека, отель);
/// площадь или улица в неё не попадают. Но дойти до места человеку нужно так же,
/// поэтому у места своя карточка: имя, расстояние по прямой и та же пешая
/// дорога по улицам, что и у объектов.
class PlaceCard extends StatelessWidget {
  const PlaceCard({
    super.key,
    required this.name,
    required this.meters,
    required this.onClose,
    required this.onRoute,
    required this.routing,
    this.route,
    this.error,
  });

  final String name;

  /// Расстояние по прямой от человека до места; null — местоположение неизвестно.
  final double? meters;

  final VoidCallback onClose;
  final VoidCallback onRoute;
  final bool routing;
  final RoutePlan? route;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const color = Color(0xFFB42318);
    final shown = route != null ? route!.meters : meters;

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
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.place, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Место на карте',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
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
            shown == null
                ? 'Расстояние неизвестно: включи геолокацию'
                : route != null
                    ? '${formatDistance(route!.meters)} · ${walkMinutes(route!.meters)} пешком'
                    : '${formatDistance(shown)} по прямой · ${walkMinutes(shown)} пешком',
            style: TextStyle(fontSize: 13, color: scheme.onSurface),
          ),
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(
              error!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFB42318)),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.icon(
                onPressed: routing ? null : onRoute,
                icon: Icon(routing ? Icons.more_horiz : Icons.directions_walk, size: 18),
                label: Text(routing ? 'Строю…' : 'Маршрут'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F7B6C)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
