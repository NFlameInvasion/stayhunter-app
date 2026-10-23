"""Правки Android-каркаса, который `flutter create` делает заново на каждой сборке.

Скрипт запускается в CI после `flutter create` и перед `flutter build`.
Он идемпотентен: повторный запуск ничего не ломает.

Что делает:
1. Добавляет разрешения — интернет, геолокация, микрофон.
2. Разрешает Android 11+ видеть службу распознавания речи.
3. Ставит видимое имя приложения «StayHunter».
4. Кладёт свою MainActivity: она глушит системный писк распознавателя.
5. Если задан KEYSTORE_PATH — включает подпись релиза нашим ключом.
"""

from __future__ import annotations

import os
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "android/app/src/main/AndroidManifest.xml"
GRADLE = ROOT / "android/app/build.gradle.kts"
MAIN_ACTIVITY = ROOT / "android/app/src/main/kotlin/ru/nflame/stayhunter/MainActivity.kt"
ICONS = ROOT / "tools/icons"

# Плотности лончера и соответствующие PNG из tools/icons.
LEGACY_ICONS = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}

ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
"""

BACKGROUND_COLOR = """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#000000</color>
</resources>
"""

PERMISSIONS = (
    '    <uses-permission android:name="android.permission.INTERNET" />\n'
    '    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />\n'
    '    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />\n'
    '    <uses-permission android:name="android.permission.RECORD_AUDIO" />\n'
)

# Android 11+ не показывает службу распознавания речи без этого запроса.
QUERIES = (
    '    <queries>\n'
    '        <intent>\n'
    '            <action android:name="android.speech.RecognitionService" />\n'
    '        </intent>\n'
    '    </queries>\n'
)

MAIN_ACTIVITY_CODE = '''package ru.nflame.stayhunter

import android.content.Context
import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Системный распознаватель пищит на каждом старте и остановке слушания.
/// Своего выключателя у него нет, поэтому глушим потоки звука на время записи
/// и возвращаем обратно после — так же, как это сделано в Aido.
class MainActivity : FlutterActivity() {
    private val audioChannel = "stayhunter/audio"
    private var muted = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "mute" -> {
                        setMuted(true)
                        result.success(null)
                    }
                    "unmute" -> {
                        setMuted(false)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun setMuted(value: Boolean) {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val direction = if (value) AudioManager.ADJUST_MUTE else AudioManager.ADJUST_UNMUTE
        audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, direction, 0)
        audio.adjustStreamVolume(AudioManager.STREAM_SYSTEM, direction, 0)
        muted = value
    }

    override fun onDestroy() {
        if (muted) setMuted(false)
        super.onDestroy()
    }
}
'''


def patch_manifest() -> None:
    text = MANIFEST.read_text(encoding="utf-8")
    missing = "".join(
        line + "\n"
        for line in PERMISSIONS.strip().splitlines()
        if line.split('name="')[1].split('"')[0] not in text
    )
    if missing:
        # Вставляем сразу после открывающего тега <manifest ...>, а не внутрь <application>.
        text = re.sub(r"(<manifest\b[^>]*>\s*\n)", r"\1" + missing, text, count=1)
    if "android.speech.RecognitionService" not in text:
        text = text.replace("    <application", QUERIES + "    <application", 1)
    text = re.sub(r'android:label="[^"]*"', 'android:label="StayHunter"', text, count=1)
    MANIFEST.write_text(text, encoding="utf-8")
    print("manifest: разрешения, распознавание и имя приложения на месте")


def write_main_activity() -> None:
    MAIN_ACTIVITY.parent.mkdir(parents=True, exist_ok=True)
    MAIN_ACTIVITY.write_text(MAIN_ACTIVITY_CODE, encoding="utf-8")
    print("MainActivity: глушение системного звука распознавателя подключено")


def patch_signing() -> None:
    if not os.environ.get("KEYSTORE_PATH"):
        print("подпись: ключ не задан, остаётся отладочная")
        return

    text = GRADLE.read_text(encoding="utf-8")
    if 'create("release")' not in text:
        block = (
            '    signingConfigs {\n'
            '        create("release") {\n'
            '            storeFile = file(System.getenv("KEYSTORE_PATH"))\n'
            '            storePassword = System.getenv("KEYSTORE_PASSWORD")\n'
            '            keyAlias = System.getenv("KEY_ALIAS")\n'
            '            keyPassword = System.getenv("KEY_PASSWORD")\n'
            '        }\n'
            '    }\n\n'
        )
        if "buildTypes {" not in text:
            sys.exit("build.gradle.kts: не нашёл блок buildTypes")
        text = text.replace("    buildTypes {", block + "    buildTypes {", 1)

    text = text.replace(
        'signingConfig = signingConfigs.getByName("debug")',
        'signingConfig = signingConfigs.getByName("release")',
    )
    GRADLE.write_text(text, encoding="utf-8")
    print("подпись: релиз подписывается нашим ключом")


def install_icons() -> None:
    """Кладёт иконку лончера в сгенерированный каркас.

    flutter create создаёт mipmap-* со своей иконкой Flutter, поэтому файлы
    перезаписываются на каждой сборке. Адаптивная иконка (Android 8+) берёт
    чёрный фон из colors.xml и прозрачный передний слой из drawable-nodpi.
    """
    if not (ICONS / "ic_launcher-192.png").exists():
        print("иконка: нет tools/icons, оставляю стандартную")
        return

    res = ROOT / "android/app/src/main/res"
    for density, size in LEGACY_ICONS.items():
        target = res / f"mipmap-{density}" / "ic_launcher.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ICONS / f"ic_launcher-{size}.png", target)

    nodpi = res / "drawable-nodpi"
    nodpi.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ICONS / "ic_launcher_foreground.png", nodpi / "ic_launcher_foreground.png")

    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(ADAPTIVE_XML, encoding="utf-8")

    colors = res / "values" / "colors.xml"
    colors.parent.mkdir(parents=True, exist_ok=True)
    if not colors.exists():
        colors.write_text(BACKGROUND_COLOR, encoding="utf-8")
    else:
        text = colors.read_text(encoding="utf-8")
        if "ic_launcher_background" not in text:
            text = text.replace(
                "</resources>",
                '    <color name="ic_launcher_background">#000000</color>\n</resources>',
                1,
            )
            colors.write_text(text, encoding="utf-8")
    print("иконка: лончер и адаптивный слой на месте")


def main() -> None:
    if not MANIFEST.exists() or not GRADLE.exists():
        sys.exit("нет Android-каркаса: сначала должен пройти flutter create")
    patch_manifest()
    write_main_activity()
    patch_signing()
    install_icons()


if __name__ == "__main__":
    main()
