import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/poi.dart';
import '../geo/distance.dart';

/// Карточка выбранного объекта: что это, где, когда открыто и как дойти.
class PoiCard extends StatelessWidget {
  const PoiCard({
    super.key,
    required this.poi,
    required this.meters,
    required this.onClose,
  });

  final Poi poi;
  final double meters;
  final VoidCallback onClose;

  Future<void> _route() async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${poi.lat},${poi.lon}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _call() async {
    await launchUrl(Uri(scheme: 'tel', path: poi.phone));
  }

  @override
  Widget build(BuildContext context) {
    final color = poi.category.color;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(color: Color(0x22000000), blurRadius: 24, offset: Offset(0, -6)),
        ],
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
                      style: const TextStyle(fontSize: 13, color: Color(0xFF667085)),
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
            '${formatDistance(meters)} · ${walkMinutes(meters)} пешком',
            style: const TextStyle(fontSize: 13, color: Color(0xFF344054)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _route,
                  icon: const Icon(Icons.directions, size: 18),
                  label: const Text('Маршрут'),
                ),
              ),
              if (poi.phone.isNotEmpty) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _call,
                  icon: const Icon(Icons.call, size: 18),
                  label: const Text('Позвонить'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
