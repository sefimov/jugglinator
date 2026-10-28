#!/bin/bash
# Сборка build/Juggler.app только средствами Command Line Tools.
#
#   scripts/bundle.sh                 release-сборка, .app, подпись, проверки, самопроверка
#   scripts/bundle.sh --no-self-test  то же без запуска Juggler --self-test
#
# Переменные окружения:
#   JUGGLER_SIGN_IDENTITY  идентичность для codesign (например, "Juggler Dev");
#                          по умолчанию подпись ad-hoc ("-").
#   JUGGLER_VERSION        CFBundleShortVersionString, по умолчанию 0.1.0.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RUN_SELF_TEST=1
for arg in "$@"; do
    case "$arg" in
        --no-self-test) RUN_SELF_TEST=0 ;;
        -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Неизвестный ключ: $arg" >&2; exit 2 ;;
    esac
done

APP_NAME="Juggler"
BUNDLE_ID="com.sefimov.juggler"
APP="$ROOT/build/$APP_NAME.app"
IDENTITY="${JUGGLER_SIGN_IDENTITY:--}"
VERSION="${JUGGLER_VERSION:-0.1.0}"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"

step() { printf '\n==> %s\n' "$*"; }

step "Сборка release (swift build -c release --product $APP_NAME)"
swift build -c release --product "$APP_NAME"
BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY="$BIN_DIR/$APP_NAME"
[ -x "$BINARY" ] || { echo "Не найден исполняемый файл: $BINARY" >&2; exit 1; }

step "Сборка $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/ru.lproj"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
    "$ROOT/scripts/Info.plist" > "$APP/Contents/Info.plist"
# Русская локализация: системные строки (меню, заголовок окна настроек) — на русском.
cat > "$APP/Contents/Resources/ru.lproj/InfoPlist.strings" <<'STRINGS'
"CFBundleDisplayName" = "Juggler";
"NSAppleEventsUsageDescription" = "Juggler читает адрес и заголовок активной вкладки Google Chrome, а в Терминале — окно и вкладку, чтобы привязать их к задаче, и переключает на них при переходе между задачами.";
STRINGS
printf 'APPL????' > "$APP/Contents/PkgInfo"

step "Проверка Info.plist (plutil -lint)"
plutil -lint "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Resources/ru.lproj/InfoPlist.strings"
[ "$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")" = "$BUNDLE_ID" ] \
    || { echo "CFBundleIdentifier не $BUNDLE_ID" >&2; exit 1; }

step "Подпись"
# Мусорные расширенные атрибуты ломают codesign --strict.
xattr -cr "$APP"
if [ "$IDENTITY" = "-" ]; then
    echo "Идентичность: ad-hoc (JUGGLER_SIGN_IDENTITY не задана)."
    echo "Разрешения Accessibility и Automation могут сбрасываться после каждой пересборки."
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
else
    echo "Идентичность: $IDENTITY"
    if ! codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$APP"; then
        echo "Не удалось подписать идентичностью «$IDENTITY»." >&2
        echo "Доступные идентичности: security find-identity -p codesigning" >&2
        echo "Как создать сертификат «Juggler Dev» — в README, раздел «Подпись»." >&2
        exit 1
    fi
fi

step "Проверка подписи (codesign --verify --strict)"
codesign --verify --strict --verbose=2 "$APP"
codesign --display --verbose=2 "$APP" 2>&1 | grep -E '^(Identifier|Signature|Authority|TeamIdentifier)=' || true

if [ "$RUN_SELF_TEST" = 1 ]; then
    step "Самопроверка ($APP_NAME --self-test)"
    "$APP/Contents/MacOS/$APP_NAME" --self-test
fi

step "Готово: $APP"
echo "Запуск: open \"$APP\""
