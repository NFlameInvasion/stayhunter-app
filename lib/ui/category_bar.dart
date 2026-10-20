import 'package:flutter/material.dart';

import '../data/poi.dart';

/// Полоса категорий над списком: одна категория или «Все».
class CategoryBar extends StatelessWidget {
  const CategoryBar({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final PoiCategory? selected;
  final ValueChanged<PoiCategory?> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      _chip(context, null, 'Все', Icons.apps),
      for (final category in PoiCategory.values)
        _chip(context, category, category.label, category.icon),
    ];

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) => items[index],
      ),
    );
  }

  Widget _chip(BuildContext context, PoiCategory? category, String label, IconData icon) {
    final isOn = category == selected;
    final color = category?.color ?? const Color(0xFF0F7B6C);
    return ChoiceChip(
      selected: isOn,
      onSelected: (_) => onChanged(category),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: isOn ? color : const Color(0xFFE4E7EC)),
      backgroundColor: Colors.white,
      selectedColor: color,
      shape: const StadiumBorder(),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isOn ? Colors.white : const Color(0xFF667085)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isOn ? FontWeight.w600 : FontWeight.w500,
              color: isOn ? Colors.white : const Color(0xFF344054),
            ),
          ),
        ],
      ),
    );
  }
}
