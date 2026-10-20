import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Кнопки поверх карты: компас (где север) и «покажи меня».
class MapControls extends StatelessWidget {
  const MapControls({
    super.key,
    required this.rotation,
    required this.onNorth,
    required this.onLocate,
    required this.locating,
  });

  /// Поворот карты в градусах: 0 — север сверху.
  final double rotation;
  final VoidCallback onNorth;
  final VoidCallback onLocate;
  final bool locating;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundButton(
          tooltip: 'Повернуть на север',
          onTap: onNorth,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.rotate(
                angle: -rotation * math.pi / 180,
                child: const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Icon(Icons.navigation, size: 19, color: accent),
                ),
              ),
              const Positioned(
                top: 2,
                child: Text(
                  'С',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: accent),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _RoundButton(
          tooltip: 'Где я',
          onTap: onLocate,
          child: locating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location, size: 22, color: accent),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.child, required this.onTap, required this.tooltip});

  final Widget child;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Center(child: child)),
        ),
      ),
    );
  }
}
