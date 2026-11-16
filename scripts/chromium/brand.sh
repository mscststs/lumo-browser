#!/usr/bin/env bash
# Apply Lumo branding to the checkout (idempotent).
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
# 108dp adaptive-icon safe zone. Package id is set by the build args
# (chrome_public_manifest_package).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
[[ -d "$CHROMIUM_SRC" ]] || die "missing $CHROMIUM_SRC"

step "app name"
python3 - "$CHROMIUM_SRC/chrome/android/java/res_chromium_base/values/channel_constants.xml" <<'PY'
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
open(p, 'w').write(s)
PY

step "launcher icons"
python3 "$REPO_ROOT/scripts/chromium/render-icons.py" \
  --res "$CHROMIUM_SRC/chrome/android/java/res_chromium_base"

# Upstream uses two different adaptive-icon recipes: ic_launcher.xml paints an
# @android:color/white background over the full-bleed layered_app_icon.png, while
# ic_launcher_round.xml uses the layered background but a *transparent* foreground
# shape. Lumo ships a dedicated gradient background layer plus a transparent logo
# layer, so normalise both icons to that (standard) recipe.
step "adaptive icon xml"
python3 - "$CHROMIUM_SRC/chrome/android/java/res_base/drawable/ic_launcher.xml" \
         "$CHROMIUM_SRC/chrome/android/java/res_base/drawable/ic_launcher_round.xml" <<'PY'
import sys

BG_WANT = '<background android:drawable="@mipmap/layered_app_icon_background"/>'
BG_OLD = '<background android:drawable="@android:color/white"/>'
FG_WANT = '<foreground android:drawable="@mipmap/layered_app_icon"/>'
FG_OLD = '<foreground android:drawable="@mipmap/layered_app_icon_foreground"/>'

for path in sys.argv[1:]:
    s = open(path).read()
    for want, old in ((BG_WANT, BG_OLD), (FG_WANT, FG_OLD)):
        if want in s:
            continue
        if old not in s:
            sys.exit('%s: unexpected adaptive-icon layer (upstream changed?)' % path)
        s = s.replace(old, want)
    open(path, 'w').write(s)
PY

step "BRANDING"
sed -i 's/^PRODUCT_FULLNAME=.*/PRODUCT_FULLNAME=Lumo/' "$CHROMIUM_SRC/chrome/app/theme/chromium/BRANDING"
sed -i 's/^PRODUCT_SHORTNAME=.*/PRODUCT_SHORTNAME=Lumo/' "$CHROMIUM_SRC/chrome/app/theme/chromium/BRANDING"

step "verify branding"
for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  [[ -s "$CHROMIUM_SRC/chrome/android/java/res_chromium_base/mipmap-$d/app_icon.png" ]] \
    || die "branding failed: mipmap-$d/app_icon.png missing"
done
[[ -s "$CHROMIUM_SRC/chrome/android/java/res_chromium_base/drawable/themed_app_icon.xml" ]] \
  || die "branding failed: themed_app_icon.xml missing"
for icon in ic_launcher.xml ic_launcher_round.xml; do
  file="$CHROMIUM_SRC/chrome/android/java/res_base/drawable/$icon"
  grep -q '@mipmap/layered_app_icon_background' "$file" \
    || die "branding failed: $icon does not use the Lumo background layer"
  grep -q '@mipmap/layered_app_icon"' "$file" \
    || die "branding failed: $icon does not use the Lumo logo layer"
done
grep -q '<string name="app_name" translatable="false">Lumo</string>' \
  "$CHROMIUM_SRC/chrome/android/java/res_chromium_base/values/channel_constants.xml" \
  || die "branding failed: app_name is not Lumo (upstream string changed?)"
grep -q '^PRODUCT_SHORTNAME=Lumo$' "$CHROMIUM_SRC/chrome/app/theme/chromium/BRANDING" \
  || die "branding failed: PRODUCT_SHORTNAME not Lumo"

step "done"
grep -E '^PRODUCT_(FULL|SHORT)NAME' "$CHROMIUM_SRC/chrome/app/theme/chromium/BRANDING"
grep -o 'name="app_name"[^<]*<\|>Lumo<' "$CHROMIUM_SRC/chrome/android/java/res_chromium_base/values/channel_constants.xml" | head -2
