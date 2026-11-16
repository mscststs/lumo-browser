#!/usr/bin/env bash
# Apply Lumo branding to the checkout (idempotent).
#
#   scripts/chromium/brand.sh
#
# * app label / widget titles  (res_chromium_base/values/channel_constants.xml)
# * launcher icons             (res_chromium_base/mipmap-*/app_icon.png)
# * adaptive icon foreground   (mipmap-*/layered_app_icon.png)
# * PRODUCT_SHORTNAME in BRANDING (about:version, titles)
#
# Package id is set by the build args (chrome_public_manifest_package).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
[[ -d "$CHROMIUM_SRC" ]] || die "missing $CHROMIUM_SRC"

ICON_SRC="${ICON_SRC:-$REPO_ROOT/../lumo/public/icon/1024.png}"
[[ -f "$ICON_SRC" ]] || die "icon not found: $ICON_SRC"
command -v convert >/dev/null || die "ImageMagick 'convert' is required for branding"

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
declare -A SIZE=([mdpi]=48 [hdpi]=72 [xhdpi]=96 [xxhdpi]=144 [xxxhdpi]=192)
for d in "${!SIZE[@]}"; do
  dir="$CHROMIUM_SRC/chrome/android/java/res_chromium_base/mipmap-$d"
  [[ -d "$dir" ]] || continue
  convert "$ICON_SRC" -resize "${SIZE[$d]}x${SIZE[$d]}" "$dir/app_icon.png"
  convert "$ICON_SRC" -resize "$(( ${SIZE[$d]} * 3 / 2 ))x$(( ${SIZE[$d]} * 3 / 2 ))" "$dir/layered_app_icon.png"
done

step "BRANDING"
sed -i 's/^PRODUCT_FULLNAME=.*/PRODUCT_FULLNAME=Lumo/' "$CHROMIUM_SRC/chrome/app/theme/chromium/BRANDING"
sed -i 's/^PRODUCT_SHORTNAME=.*/PRODUCT_SHORTNAME=Lumo/' "$CHROMIUM_SRC/chrome/app/theme/chromium/BRANDING"

step "verify branding"
grep -q '<string name="app_name" translatable="false">Lumo</string>' \
  "$CHROMIUM_SRC/chrome/android/java/res_chromium_base/values/channel_constants.xml" \
  || die "branding failed: app_name is not Lumo (upstream string changed?)"
grep -q '^PRODUCT_SHORTNAME=Lumo$' "$CHROMIUM_SRC/chrome/app/theme/chromium/BRANDING" \
  || die "branding failed: PRODUCT_SHORTNAME not Lumo"

step "done"
grep -E '^PRODUCT_(FULL|SHORT)NAME' "$CHROMIUM_SRC/chrome/app/theme/chromium/BRANDING"
grep -o 'name="app_name"[^<]*<\|>Lumo<' "$CHROMIUM_SRC/chrome/android/java/res_chromium_base/values/channel_constants.xml" | head -2
