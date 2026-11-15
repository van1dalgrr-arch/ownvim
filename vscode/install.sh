#!/bin/sh
# ownvim в VS Code — установка (можно запускать сколько угодно раз):
#   - отдельная копия VS Code: ~/.local/share/ownvim/vscode/{data,extensions}
#   - settings.json и keybindings.json — ссылками на vscode/User (правишь в репо — применяется сразу)
#   - расширения из extensions.txt и своё расширение ownvim (vscode/extension) — ссылкой, пересборка подхватывается
#   - команда ownvim-code и приложение «ownvim Code» в ~/Applications
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="${OWNVIM_CODE_HOME:-$HOME/.local/share/ownvim/vscode}"
CODE="code --user-data-dir $DATA/data --extensions-dir $DATA/extensions"
mkdir -p "$DATA/data/User" "$DATA/extensions"

echo "▸ настройки"
for f in settings.json keybindings.json; do ln -sfn "$HERE/User/$f" "$DATA/data/User/$f"; done

echo "▸ своё расширение"
(cd "$HERE/extension" && { [ -d node_modules ] || npm ci --no-audit --no-fund; } && npm run --silent build >/dev/null)
VER=$(node -p "require('$HERE/extension/package.json').version")
rm -rf "$DATA/extensions"/van1dal.ownvim-*
ln -sfn "$HERE/extension" "$DATA/extensions/van1dal.ownvim-$VER"
# VS Code помнит расширения в extensions.json — ссылку надо туда вписать, иначе её не видно
node -e '
const fs = require("fs"), [file, dir, ver] = process.argv.slice(1);
let list = []; try { list = JSON.parse(fs.readFileSync(file, "utf8")); } catch {}
list = list.filter((e) => e.identifier?.id !== "van1dal.ownvim");
list.push({ identifier: { id: "van1dal.ownvim" }, version: ver, location: { $mid: 1, path: dir, scheme: "file" }, relativeLocation: "van1dal.ownvim-" + ver, metadata: { source: "vsix", installedTimestamp: Date.now() } });
fs.writeFileSync(file, JSON.stringify(list));
' "$DATA/extensions/extensions.json" "$DATA/extensions/van1dal.ownvim-$VER" "$VER"

echo "▸ расширения"
have=$($CODE --list-extensions 2>/dev/null | tr 'A-Z' 'a-z')
grep -v '^\s*#' "$HERE/extensions.txt" | grep -v '^\s*$' | while read -r ext; do
  low=$(echo "$ext" | tr 'A-Z' 'a-z')
  if echo "$have" | grep -qx "$low"; then continue; fi
  $CODE --install-extension "$ext" --force >/dev/null 2>&1 && echo "  + $ext" || echo "  ✗ $ext — не поставилось"
done

echo "▸ команда ownvim-code"
BIN="${OWNVIM_CODE_BIN:-/opt/homebrew/bin}"
[ -w "$BIN" ] || BIN="$HOME/.local/bin"
mkdir -p "$BIN"
ln -sfn "$HERE/bin/ownvim-code" "$BIN/ownvim-code"

echo "▸ приложение ~/Applications/ownvim Code.app"
APP="$HOME/Applications/ownvim Code.app"
mkdir -p "$HOME/Applications"
rm -rf "$APP"
osacompile -o "$APP" -e "do shell script \"PATH=/opt/homebrew/bin:/usr/local/bin:\$PATH; '$HERE/bin/ownvim-code' --new-window >/dev/null 2>&1 &\"" >/dev/null
ICON="/Applications/Visual Studio Code.app/Contents/Resources/Code.icns"
[ -f "$ICON" ] && cp "$ICON" "$APP/Contents/Resources/applet.icns"

echo "готово: ownvim-code . — или «ownvim Code» в Launchpad / Spotlight"
