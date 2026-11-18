#!/usr/bin/env bash
# Apply Lumo branding to the checkout (idempotent, and *quiet when nothing
# changed*: every rewrite is content-compared first, so repeated builds do not
# invalidate resources/PNGs just because a file was touched).
#
#   scripts/chromium/brand.sh
#
# * app label / widget titles  (res_chromium_base/values/channel_constants.xml)
# * launcher icons             (mipmap-*/app_icon.png, squircle baked)
# * adaptive icon layers       (mipmap-*/layered_app_icon{,_background}.png)
# * themed (monochrome) icon   (drawable/themed_app_icon.xml)
# * PRODUCT_SHORTNAME in BRANDING (about:version, titles)
#
# Icon artwork lives in scripts/chromium/branding/*.svg and is rendered by
# scripts/chromium/render-icons.py (librsvg), which also enforces the Android
# 108dp adaptive-icon safe zone.
# Package id is set by the build args (chrome_public_manifest_package).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
[[ -d "$CHROMIUM_SRC" ]] || die "missing $CHROMIUM_SRC"

# write_if_changed <path>  (new content on stdin)
# Avoids mtime churn on files that dominate the Android resource pipeline; also
# gives a line of output only when something actually changed.
write_if_changed() {
  local path="$1" tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  if [[ -f "$path" ]] && cmp -s "$tmp" "$path"; then
    rm -f "$tmp"
    return 0
  fi
  cat "$tmp" > "$path"
  rm -f "$tmp"
  log "updated ${path#"$CHROMIUM_SRC/"}"
  return 0
}

RES_BASE="$CHROMIUM_SRC/chrome/android/java/res_chromium_base"

step "app name"
CHANNEL_XML="$RES_BASE/values/channel_constants.xml"
python3 - "$CHANNEL_XML" <<'PY' | write_if_changed "$CHANNEL_XML"
import sys
p = sys.argv[1]
s = open(p).read()
for old, new in [
    ('<string name="app_name" translatable="false">Chromium</string>',
     '<string name="app_name" translatable="false">Lumo</string>'),
    ('<string name="bookmark_widget_title" translatable="false">Chromium bookmarks</string>',
     '<string name="bookmark_widget_title" translatable="false">Lumo bookmarks</string>'),
    ('<string name="search_widget_title" translatable="false">Chromium search</string>',
     '<string name="search_widget_title" translatable="false">Lumo search</string>'),
    ('<string name="quick_action_search_widget_title" translatable="false">Chromium quick action search</string>',
     '<string name="quick_action_search_widget_title" translatable="false">Lumo quick action search</string>'),
]:
    s = s.replace(old, new)
sys.stdout.write(s)
PY

step "launcher icons"
python3 "$REPO_ROOT/scripts/chromium/render-icons.py" --res "$RES_BASE"

# Upstream uses two different adaptive-icon recipes: ic_launcher.xml paints an
# @android:color/white background over the full-bleed layered_app_icon.png, while
# ic_launcher_round.xml uses the layered background but a *transparent* foreground
# shape. Lumo ships a dedicated gradient background layer plus a transparent logo
# layer, so normalise both icons to that (standard) recipe.
step "adaptive icon xml"
for icon in ic_launcher.xml ic_launcher_round.xml; do
  file="$CHROMIUM_SRC/chrome/android/java/res_base/drawable/$icon"
  python3 - "$file" <<'PY' | write_if_changed "$file"
import sys

BG_WANT = '<background android:drawable="@mipmap/layered_app_icon_background"/>'
BG_OLD = '<background android:drawable="@android:color/white"/>'
FG_WANT = '<foreground android:drawable="@mipmap/layered_app_icon"/>'
FG_OLD = '<foreground android:drawable="@mipmap/layered_app_icon_foreground"/>'

path = sys.argv[1]
s = open(path).read()
for want, old in ((BG_WANT, BG_OLD), (FG_WANT, FG_OLD)):
    if want in s:
        continue
    if old not in s:
        sys.exit('%s: unexpected adaptive-icon layer (upstream changed?)' % path)
    s = s.replace(old, want)
sys.stdout.write(s)
PY
done

step "BRANDING"
BRANDING="$CHROMIUM_SRC/chrome/app/theme/chromium/BRANDING"
python3 - "$BRANDING" <<'PY' | write_if_changed "$BRANDING"
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r'(?m)^PRODUCT_FULLNAME=.*$', 'PRODUCT_FULLNAME=Lumo', s)
s = re.sub(r'(?m)^PRODUCT_SHORTNAME=.*$', 'PRODUCT_SHORTNAME=Lumo', s)
sys.stdout.write(s)
PY

step "verify branding"
for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  [[ -s "$RES_BASE/mipmap-$d/app_icon.png" ]] \
    || die "branding failed: mipmap-$d/app_icon.png missing"
done
[[ -s "$RES_BASE/drawable/themed_app_icon.xml" ]] \
  || die "branding failed: themed_app_icon.xml missing"
for icon in ic_launcher.xml ic_launcher_round.xml; do
  file="$CHROMIUM_SRC/chrome/android/java/res_base/drawable/$icon"
  grep -q '@mipmap/layered_app_icon_background' "$file" \
    || die "branding failed: $icon does not use the Lumo background layer"
  grep -q '@mipmap/layered_app_icon"' "$file" \
    || die "branding failed: $icon does not use the Lumo logo layer"
done
grep -q '<string name="app_name" translatable="false">Lumo</string>' "$CHANNEL_XML" \
  || die "branding failed: app_name is not Lumo (upstream string changed?)"
grep -q '^PRODUCT_SHORTNAME=Lumo$' "$BRANDING" \
  || die "branding failed: PRODUCT_SHORTNAME not Lumo"

step "done"
grep -E '^PRODUCT_(FULL|SHORT)NAME' "$BRANDING"
grep -o 'name="app_name"[^<]*<\|>Lumo<' "$CHANNEL_XML" | head -2
