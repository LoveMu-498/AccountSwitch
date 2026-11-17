#!/usr/bin/env bash
set -euo pipefail

mode="${1:-run}"
case "$mode" in
    run|--verify|--debug|--logs|--telemetry|--package) ;;
    *) echo "Usage: $0 [--verify|--debug|--logs|--telemetry|--package]" >&2; exit 2 ;;
esac

cd "$(dirname "${BASH_SOURCE[0]}")/.."
app="$PWD/dist/AccountSwitch.app"
configuration=debug
signing_identity="${ACCOUNT_SWITCH_SIGN_IDENTITY:-}"
if [[ "$mode" == --package ]]; then
    app="$PWD/dist/release/AccountSwitch.app"
    configuration=release
    signing_identity=-
elif [[ -z "$signing_identity" ]]; then
    signing_identity="$(security find-identity -v -p codesigning | awk '/"Apple Development:/ {id=$2; count++} END {if (count == 1) print id}')"
fi
signing_identity="${signing_identity:--}"
binary="$app/Contents/MacOS/AccountSwitch"

swift build -c "$configuration"
build_binary="$(swift build -c "$configuration" --show-bin-path)/AccountSwitch"

if [[ "$mode" != --package ]] && pgrep -x AccountSwitch >/dev/null; then
    pkill -TERM -x AccountSwitch
    for attempt in {1..20}; do
        pgrep -x AccountSwitch >/dev/null || break
        sleep 0.1
    done
    if pgrep -x AccountSwitch >/dev/null; then
        echo "AccountSwitch is still running." >&2
        exit 1
    fi
fi

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp -f "$build_binary" "$binary"
cp -f script/Info.plist "$app/Contents/Info.plist"
cp -f script/AccountSwitch.icns "$app/Contents/Resources/AccountSwitch.icns"
cp -f Sources/AccountSwitch/Resources/Storefronts.json "$app/Contents/Resources/Storefronts.json"
cp -f LICENSE NOTICE "$app/Contents/Resources/"
if [[ "$mode" == --package ]]; then
    strip -S "$binary"
    codesign --force --timestamp=none --sign "$signing_identity" "$app"
    codesign --verify --strict "$app"
    printf '%s\n' "$app"
    exit 0
fi

codesign --force --sign "$signing_identity" "$app"
open "$app"

case "$mode" in
    --verify)
        codesign --verify --strict "$app"
        pgrep -x AccountSwitch
        ;;
    --debug) lldb --attach-name AccountSwitch ;;
    --logs|--telemetry) /usr/bin/log stream --info --style compact --predicate 'process == "AccountSwitch"' ;;
esac
