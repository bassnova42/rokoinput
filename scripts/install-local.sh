#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
if pgrep -x RokoInput >/dev/null; then
    echo "Quit Roko Input before installing the local build."
    exit 1
fi
zsh scripts/build.sh
DEST="$HOME/Library/Input Methods/Roko Input.app"
mkdir -p "$(dirname "$DEST")"
if [[ -e "$DEST" ]]; then
    BACKUP="$HOME/Library/Application Support/Roko Input/Backups/$(date +%Y%m%d-%H%M%S)-$$.app"
    mkdir -p "$(dirname "$BACKUP")"
    mv "$DEST" "$BACKUP"
fi
ditto "build/Roko Input.app" "$DEST"
"$DEST/Contents/MacOS/RokoInput" --register-input-source
echo "Installed local build: $DEST. Add it in Keyboard > Text Input if necessary."
