#!/bin/bash
# Instala ou atualiza o FigCraft Habittart neste Mac (Apple Silicon).
# Baixa a versao mais recente de https://github.com/habittart/figcraft-habittart/releases, troca o executavel do
# /Applications/FigCraft.app pelo corrigido, instala o figcraft-cli e o proxy do MCP em ~/bin,
# liga o MCP no app do Claude e agenda a verificacao automatica (no login e a cada 6 horas).
#
#   Primeira vez (Terminal):
#   curl -fsSL https://raw.githubusercontent.com/habittart/figcraft-habittart/main/scripts/mac/atualizar-figcraft.command | bash
#
# Com --check (o agendamento usa assim) so verifica; se houver o que instalar, abre este script no
# Terminal, que tem a permissao de "Gerenciamento de Apps" para alterar o FigCraft.app.
REPO="habittart/figcraft-habittart"
PORT=7979
APP="/Applications/FigCraft.app"
STATE="$HOME/Library/Application Support/FigCraft-Habittart"
mkdir -p "$STATE" "$HOME/bin"
LOG="$STATE/update.log"
if [ -t 1 ]; then exec > >(tee -a "$LOG") 2>&1; else exec >>"$LOG" 2>&1; fi
echo "== $(date) $*"
set -e

json() { /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); $1"; }
REL=$(curl -fsSL -H 'User-Agent: figcraft-habittart' "https://api.github.com/repos/$REPO/releases/latest") || { echo "sem rede ou sem versoes ainda"; exit 0; }
TAG=$(printf '%s' "$REL" | json 'print(d["tag_name"])')
URL=$(printf '%s' "$REL" | json 'print(next(a["browser_download_url"] for a in d["assets"] if a["name"].endswith("macos-arm64.zip")))')
UP=${TAG%%-habittart*}

EXE_NAME=$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleExecutable 2>/dev/null || echo FigCraft)
EXE="$APP/Contents/MacOS/$EXE_NAME"
CUR=$(cat "$STATE/installed.txt" 2>/dev/null || true)
# The corrected executable must run inside the official bundle of the same version (resources,
# Info.plist): if the FigCraft.app here is another version, the official one of $UP is reinstalled.
APPVER=$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)
PATCHED=0
[ -f "$EXE" ] && grep -q "colour matching: tagged" "$EXE" && PATCHED=1
if [ "$TAG" = "$CUR" ] && [ "$PATCHED" = 1 ] && [ "$APPVER" = "${UP#v}" ] && [ -x "$HOME/bin/figcraft-cli-bin" ]; then
  echo "FigCraft ja esta na versao mais recente ($TAG)"; exit 0
fi

if [ "$1" = "--check" ]; then
  echo "atualizacao necessaria ($CUR -> $TAG, corrigido=$PATCHED): abrindo no Terminal"
  cp "$0" "$STATE/atualizar-figcraft.command" 2>/dev/null || true
  chmod +x "$STATE/atualizar-figcraft.command"
  /usr/bin/osascript -e 'display notification "Instalando a versao corrigida do FigCraft" with title "FigCraft"' || true
  /usr/bin/open -a Terminal "$STATE/atualizar-figcraft.command"
  exit 0
fi

TMP=$(mktemp -d)
echo "== baixando $TAG"
curl -fsSL -o "$TMP/fc.zip" "$URL"
/usr/bin/ditto -x -k "$TMP/fc.zip" "$TMP/fc"

if [ ! -d "$APP" ] || [ "$APPVER" != "${UP#v}" ]; then
  echo "== instalando o FigCraft.app oficial $UP (havia: ${APPVER:-nenhum})"
  curl -fsSL -o "$TMP/fc.dmg" "https://github.com/storytold/figcraft/releases/download/$UP/figcraft-${UP#v}-macos-universal.dmg"
  MNT=$(/usr/bin/hdiutil attach -nobrowse -readonly "$TMP/fc.dmg" | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)
  [ -d "$MNT/FigCraft.app" ] || { echo "nao achei o FigCraft.app no instalador oficial"; exit 1; }
  rm -rf "$APP.new" && /usr/bin/ditto "$MNT/FigCraft.app" "$APP.new"
  rm -rf "$APP" && mv "$APP.new" "$APP"
  PATCHED=0
  /usr/bin/hdiutil detach "$MNT" -quiet || true
  EXE_NAME=$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleExecutable)
  EXE="$APP/Contents/MacOS/$EXE_NAME"
fi

echo "== instalando o app corrigido"
BK="$STATE/FigCraft-binario-original"
[ -f "$BK" ] || { [ "$PATCHED" = 0 ] && [ -f "$EXE" ] && cp "$EXE" "$BK" || true; }
cp "$TMP/fc/figcraft" "$EXE.new" && chmod +x "$EXE.new" && mv -f "$EXE.new" "$EXE"
/usr/bin/xattr -cr "$APP" 2>/dev/null || true
/usr/bin/codesign --force --deep --sign - "$APP"

echo "== instalando figcraft-cli e o proxy do MCP em ~/bin"
for pair in "figcraft-cli:figcraft-cli-bin" "figcraft-mcp:figcraft-cli"; do
  src=${pair%%:*}; dst=${pair##*:}
  cp "$TMP/fc/$src" "$HOME/bin/.$dst.new" && chmod +x "$HOME/bin/.$dst.new"
  /usr/bin/xattr -c "$HOME/bin/.$dst.new" 2>/dev/null || true
  mv -f "$HOME/bin/.$dst.new" "$HOME/bin/$dst"
done
cp "$TMP/fc/atualizar-figcraft.command" "$STATE/atualizar-figcraft.command" && chmod +x "$STATE/atualizar-figcraft.command"
printf '#!/bin/bash\nopen -n -a "%s" --args --control %s\n' "$APP" "$PORT" > "$HOME/bin/abrir-figcraft-claude.command"
chmod +x "$HOME/bin/abrir-figcraft-claude.command"

echo "== MCP no app do Claude"
CFG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
mkdir -p "$(dirname "$CFG")"
/usr/bin/python3 - "$CFG" "$HOME/bin/figcraft-cli" "$PORT" <<'PY'
import json, os, sys, shutil, time
p, cmd, port = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = {}
if os.path.exists(p) and open(p).read().strip():
    cfg = json.load(open(p))
want = {"command": cmd, "args": ["mcp", "--attach", port]}
if cfg.get("mcpServers", {}).get("figcraft") != want:
    if os.path.exists(p): shutil.copy(p, p + ".backup-" + time.strftime("%Y%m%d%H%M%S"))
    cfg.setdefault("mcpServers", {})["figcraft"] = want
    json.dump(cfg, open(p, "w"), indent=2)
    print("config do Claude atualizada (reinicie o app do Claude)")
PY

echo "== verificacao automatica (login e a cada 6 h)"
PL="$HOME/Library/LaunchAgents/com.habittart.figcraft-update.plist"
mkdir -p "$(dirname "$PL")"
cat > "$PL" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.habittart.figcraft-update</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$STATE/atualizar-figcraft.command</string><string>--check</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>21600</integer>
</dict></plist>
PL
/bin/launchctl bootout "gui/$(id -u)" "$PL" 2>/dev/null || true
/bin/launchctl bootstrap "gui/$(id -u)" "$PL" 2>/dev/null || /bin/launchctl load "$PL" 2>/dev/null || true

echo "$TAG" > "$STATE/installed.txt"
rm -rf "$TMP"
echo "== PRONTO: FigCraft $TAG (reabra o FigCraft para usar a versao nova)"
/usr/bin/osascript -e "display notification \"FigCraft $TAG instalado\" with title \"FigCraft\"" || true
