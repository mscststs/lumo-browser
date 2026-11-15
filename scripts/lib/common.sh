#!/usr/bin/env bash
# Shared environment for all scripts. Source it, don't execute it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

# --- Chromium source -------------------------------------------------------
export CHROMIUM_ROOT="${CHROMIUM_ROOT:-$HOME/chromium}"
export CHROMIUM_SRC="${CHROMIUM_SRC:-$CHROMIUM_ROOT/src}"
export DEPOT_TOOLS="${DEPOT_TOOLS:-$HOME/depot_tools}"
export PATH="$DEPOT_TOOLS:$PATH"

# --- Android ---------------------------------------------------------------
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/android-sdk}"
export PATH="$ANDROID_SDK_ROOT/platform-tools:$PATH"
export DEVICE_SERIAL="${DEVICE_SERIAL:-$(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')}"

# --- Product ---------------------------------------------------------------
export APK_OUT="${APK_OUT:-$REPO_ROOT/artifacts/apk}"
# Adopt package/activity from the last built APK when available.
if [[ -z "${PRODUCT_PKG:-}" && -f "${APK_OUT:-}/meta.env" ]]; then
  # shellcheck disable=SC1091
  source "$APK_OUT/meta.env"
fi
export PRODUCT_PKG="${PRODUCT_PKG:-dev.lumo.browser}"

# Reference extensions (siblings of this repo).
export EXT_LUMO_DIR="${EXT_LUMO_DIR:-$REPO_ROOT/../lumo}"
export EXT_US_DIR="${EXT_US_DIR:-$REPO_ROOT/../lumo-userscript-manager}"

# --- Output ----------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'
else
  C_RESET=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""
fi

log()  { printf '%s[lumo]%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%s[fail]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
step() { printf '\n%s== %s ==%s\n' "$C_GREEN" "$*" "$C_RESET"; }

# --- Device helpers --------------------------------------------------------
need_device() {
  [[ -n "${DEVICE_SERIAL:-}" ]] || die "no adb device (check: adb devices)"
}

# adb on the selected device
D() { adb -s "$DEVICE_SERIAL" "$@"; }
# adb as root (Magisk). Android 11 + MIUI: /data/data is not reachable from
# the magisk domain, so extension payloads live in the app's *external* dir.
DR() { D shell su -c "$*"; }

shot() { # shot <path>
  local out="$1"; mkdir -p "$(dirname "$out")"
  D exec-out screencap -p > "$out"
  [[ -s "$out" ]] || die "screencap failed"
  log "screenshot: $out"
}

ui_dump() { # ui_dump <path>
  local out="$1"; mkdir -p "$(dirname "$out")"
  DR "uiautomator dump /sdcard/ui.xml >/dev/null 2>&1" || true
  D pull /sdcard/ui.xml "$out" >/dev/null 2>&1 || true
}

# tap_text <text> [--desc] : find a node by text/content-desc and tap its center.
tap_text() {
  local needle="$1"
  local tmp; tmp="$(mktemp)"
  ui_dump "$tmp"
  local xy
  xy="$(python3 - "$tmp" "$needle" <<'PY'
import re, sys
path, needle = sys.argv[1], sys.argv[2]
try:
    s = open(path, encoding='utf-8', errors='ignore').read()
except OSError:
    sys.exit(1)
for m in re.finditer(r'<node[^>]*>', s):
    tag = m.group(0)
    t = re.search(r'text="([^"]*)"', tag)
    d = re.search(r'content-desc="([^"]*)"', tag)
    val = (t.group(1) if t else '') or (d.group(1) if d else '')
    if needle and needle in val:
        b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', tag)
        if not b:
            continue
        x1, y1, x2, y2 = map(int, b.groups())
        if x2 > x1 and y2 > y1:
            print((x1 + x2) // 2, (y1 + y2) // 2)
            break
PY
)"
  rm -f "$tmp"
  [[ -n "$xy" ]] || return 1
  DR "input tap $xy"
  log "tapped '$needle' at $xy"
}

# Tap the switch/checkbox that sits on the same row as <label> (WebUI settings).
tap_switch_near() {
  local label="$1"
  local tmp; tmp="$(mktemp)"
  ui_dump "$tmp"
  local xy
  xy="$(python3 - "$tmp" "$label" <<'PY2'
import re, sys
path, label = sys.argv[1], sys.argv[2]
s = open(path, encoding='utf-8', errors='ignore').read()
row_y = None
for m in re.finditer(r'<node[^>]*>', s):
    tag = m.group(0)
    t = re.search(r'text="([^"]*)"', tag)
    if t and label in t.group(1):
        b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', tag)
        if b:
            row_y = (int(b.group(2)) + int(b.group(4))) // 2
            break
if row_y is None:
    sys.exit(1)
best = None
for m in re.finditer(r'<node[^>]*>', s):
    tag = m.group(0)
    c = re.search(r'class="([^"]*)"', tag)
    if not c or 'Switch' not in c.group(1):
        continue
    b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', tag)
    if not b:
        continue
    y = (int(b.group(2)) + int(b.group(4))) // 2
    if abs(y - row_y) <= 40:
        best = ((int(b.group(1)) + int(b.group(3))) // 2, y)
        break
if best is None:
    sys.exit(1)
print(*best)
PY2
)"
  rm -f "$tmp"
  [[ -n "$xy" ]] || return 1
  DR "input tap $xy"
  log "toggled switch next to '$label' at $xy"
}

# Open the extensions toolbar menu (per-extension switches + manage entries).
open_extensions_menu() {
  tap_text "自定义及控制" || tap_text "Customize and control" || tap_text "已允许在此网站上使用扩展程序" \
    || tap_text "允许在此网站上使用扩展程序" || { warn "cannot open overflow/extensions menu"; return 1; }
  sleep 1
  tap_text "打开扩展程序菜单" || tap_text "Open extensions menu" || true
  sleep 2
}

# Open chrome://extensions in the running browser using the overflow menu
# (chrome:// URLs are rejected by the intent dispatcher on release builds).
open_extensions_page() {
  tap_text "自定义及控制" || tap_text "Customize and control" || tap_text "更多选项" || \
    tap_text "More options" || tap_text "主菜单" || { warn "overflow button not found"; return 1; }
  sleep 1
  # Lumo/Chromium build: the overflow menu exposes "打开扩展程序菜单" directly.
  if ! tap_text "打开扩展程序菜单" && ! tap_text "Open extensions menu"; then
    # Older layout: a nested "扩展程序" submenu.
    tap_text "扩展程序" || tap_text "Extensions" || { warn "extensions menu item not found"; return 1; }
    sleep 1
    tap_text "打开扩展程序菜单" || tap_text "Open extensions menu" || true
  fi
  sleep 2
  tap_text "管理扩展程序" || tap_text "Manage extensions" || { warn "manage-extensions entry not found"; return 1; }
  sleep 3
}

# Launch the browser main activity.
launch_browser() {
  DR "am force-stop $PRODUCT_PKG" || true
  if DR "monkey -p $PRODUCT_PKG -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1; then
    :
  elif [[ -n "${MAIN_ACTIVITY:-}" ]]; then
    DR "am start -n $PRODUCT_PKG/$MAIN_ACTIVITY" >/dev/null
  else
    die "cannot launch $PRODUCT_PKG (no launcher activity)"
  fi
  log "launched $PRODUCT_PKG"
}

# Open a URL / chrome:// page in the browser.
open_url() { DR "am start -a android.intent.action.VIEW -d '$1' -n $PRODUCT_PKG/${MAIN_ACTIVITY:-com.google.android.apps.chrome.Main}" >/dev/null; }

# Wait until the browser process is the focused window (max $2 seconds).
wait_focus() {
  local deadline=$(( $(date +%s) + ${2:-30} ))
  while (( $(date +%s) < deadline )); do
    if DR "dumpsys window" 2>/dev/null | grep -q "mCurrentFocus=.*$PRODUCT_PKG"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# Set of extension UI strings currently in the view hierarchy (bearer of truth
# for "did the extension toolbar render").
ext_ui_strings() {
  local tmp; tmp="$(mktemp)"
  ui_dump "$tmp"
  grep -o 'text="[^"]*"' "$tmp" 2>/dev/null | sed 's/text="//;s/"$//' | sort -u
  rm -f "$tmp"
}
