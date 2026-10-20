"""Правки Android-каркаса, который `flutter create` делает заново на каждой сборке.

Скрипт запускается в CI после `flutter create` и перед `flutter build`.
Он идемпотентен: повторный запуск ничего не ломает.

Что делает:
1. Добавляет разрешение INTERNET — без него release-сборка не может открыть карту.
2. Ставит видимое имя приложения «StayHunter».
3. Если задан KEYSTORE_PATH — включает подпись релиза нашим ключом, иначе
   остаётся отладочная подпись (сборка соберётся, но не встанет поверх).
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "android/app/src/main/AndroidManifest.xml"
GRADLE = ROOT / "android/app/build.gradle.kts"

PERMISSIONS = (
    '    <uses-permission android:name="android.permission.INTERNET" />\n'
    '    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />\n'
    '    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />\n'
)


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
    text = re.sub(r'android:label="[^"]*"', 'android:label="StayHunter"', text, count=1)
    MANIFEST.write_text(text, encoding="utf-8")
    print("manifest: интернет, геолокация и имя приложения на месте")


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


def main() -> None:
    if not MANIFEST.exists() or not GRADLE.exists():
        sys.exit("нет Android-каркаса: сначала должен пройти flutter create")
    patch_manifest()
    patch_signing()


if __name__ == "__main__":
    main()
