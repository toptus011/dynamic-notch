#!/bin/bash
# zrob-dmg.sh – kompiluje Dynamic Notch i tworzy instalator DynamicNotch.dmg
# Użycie: w Terminalu wpisz  bash ~/Downloads/DynamicNotch/zrob-dmg.sh

set -e
cd "$(dirname "$0")"

EXE="DynamicNotch"
APPNAME="Dynamic Notch"
BUILD="build"
BUNDLE="$BUILD/$APPNAME.app"
STAGE="$BUILD/dmg"
DMG="DynamicNotch.dmg"
ID="pl.bulka.dynamicnotch"

echo "▶ Sprawdzam narzędzia…"
if ! command -v swiftc >/dev/null 2>&1; then
    echo "Brak kompilatora Swift. Za chwilę otworzy się instalator narzędzi Xcode."
    echo "Po instalacji uruchom ten skrypt ponownie."
    xcode-select --install || true
    exit 1
fi

echo "▶ Kompiluję…"
rm -rf "$BUILD" "$DMG"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

swiftc -O -swift-version 5 \
    -target arm64-apple-macos13.0 \
    -framework Cocoa -framework SwiftUI -framework Combine \
    -framework CoreAudio -framework CoreMediaIO -framework IOBluetooth -framework IOKit -framework EventKit -framework UniformTypeIdentifiers -framework UserNotifications \
    -framework Carbon -framework ServiceManagement -framework ApplicationServices \
    -o "$BUNDLE/Contents/MacOS/$EXE" \
    Sources/*.swift

cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
# Opisy zgód po angielsku (gdy system nie jest po polsku)
cp -R Resources/en.lproj Resources/pl.lproj "$BUNDLE/Contents/Resources/"
# Opis agenta w tle (start przy logowaniu + restart po awarii)
mkdir -p "$BUNDLE/Contents/Library/LaunchAgents"
cp Resources/pl.bulka.dynamicnotch.agent.plist "$BUNDLE/Contents/Library/LaunchAgents/"

echo "▶ Podpisuję (lokalnie, ze stałym identyfikatorem)…"
# Stały wymóg podpisu sprawia, że uprawnienia przetrwają kolejne aktualizacje.
if ! codesign --force --sign - --identifier "$ID" \
        --requirements "=designated => identifier \"$ID\"" "$BUNDLE" 2>/dev/null; then
    echo "  (podpis ze stałym identyfikatorem niedostępny – używam zwykłego podpisu)"
    codesign --force --sign - --identifier "$ID" "$BUNDLE"
fi
codesign --verify "$BUNDLE" && echo "  podpis poprawny"

echo "▶ Tworzę instalator .dmg…"
mkdir -p "$STAGE"
cp -R "$BUNDLE" "$STAGE/"
ln -s /Applications "$STAGE/Aplikacje"
cp README.md "$STAGE/Przeczytaj mnie.md"

hdiutil create -volname "$APPNAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "✅ Gotowe: $(pwd)/$DMG"
echo "Otwieram instalator – przeciągnij „$APPNAME” na folder Aplikacje."
open "$DMG"
