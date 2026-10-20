import 'package:flutter/services.dart';

/// Системный звук распознавателя (писк при старте и остановке слушания).
///
/// Своего выключателя у Android нет, поэтому нативная часть глушит потоки
/// STREAM_MUSIC и STREAM_SYSTEM на время записи. Если канала нет (например,
/// приложение запущено в браузере), вызовы молча ничего не делают.
const _channel = MethodChannel('stayhunter/audio');

Future<void> muteDeviceSound() async {
  try {
    await _channel.invokeMethod<void>('mute');
  } catch (_) {
    // Не Android или канала нет — не беда.
  }
}

Future<void> unmuteDeviceSound() async {
  try {
    await _channel.invokeMethod<void>('unmute');
  } catch (_) {
    // Не Android или канала нет — не беда.
  }
}
