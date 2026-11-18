#!/usr/bin/env bash
# Single source of truth for Chromium's command line on the device.
#
#   scripts/chromium/flags.sh compose [extra flags...]   # print the command line
#   scripts/chromium/flags.sh push    [extra flags...]   # write it + enable the debug-app handshake
#   scripts/chromium/flags.sh show                       # what the device has right now
#   scripts/chromium/flags.sh clear                      # remove it (stock Chromium behaviour)
#   scripts/chromium/flags.sh presets                    # runtime-togglable Lumo features
#
# Env:
#   LUMO_EXTENSIONS        comma list of extension dirs; absolute paths win,
#                          other names resolve under LUMO_EXT_ROOT.
#                          Default: "lumo,lumo-userscript-manager"; "" = load none.
#   LUMO_EXT_ROOT          default /sdcard/Android/data/$PRODUCT_PKG/files/ext
#   LUMO_FEATURES          comma list -> --enable-features=...
#   LUMO_DISABLE_FEATURES  comma list -> --disable-features=...
#   LUMO_FLAGS             extra flags, split on whitespace
#   LUMO_CMDLINE_PATH      default /data/local/tmp/chrome-command-line
#
# Why this exists: base::Feature defaults are compiled into the binary, but every
# feature that is exposed to Java can also be flipped at runtime from here. That
# means behaviour changes (side panel on/off, verbose logs, ...) do NOT need a
# Chromium rebuild — only structural code gaps do. See docs/05-build.md.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

CMDLINE_PATH="${LUMO_CMDLINE_PATH:-/data/local/tmp/chrome-command-line}"
EXT_ROOT="${LUMO_EXT_ROOT:-/sdcard/Android/data/$PRODUCT_PKG/files/ext}"

# Runtime-toggleable features that matter to this product. The value on the
# right is the compiled default *after* our patches; anything listed here can be
# flipped from the command line without rebuilding the kernel.
PRESETS=$(cat <<'EOF'
EnableAndroidSidePanel                  default:ON   (patches/0003) Android side panel
EnableAndroidSidePanelManualResizing    default:ON   (patches/0003) drag-to-resize on wide screens
EnableAndroidSidePanelDevFeature         default:OFF  debug entry points for the panel
EnableAndroidSidePanelLogs               default:OFF  verbose side panel logging
EOF
)

compose() {
  local parts=("chrome") names=() name joined="" ext
  local exts="${LUMO_EXTENSIONS-lumo,lumo-userscript-manager}"

  if [[ -n "$exts" ]]; then
    IFS=',' read -ra names <<< "$exts"
    for name in "${names[@]}"; do
      [[ -n "$name" ]] || continue
      if [[ "$name" == /* ]]; then ext="$name"; else ext="$EXT_ROOT/$name"; fi
      joined+="${joined:+,}$ext"
    done
    [[ -n "$joined" ]] && parts+=("--load-extension=$joined")
  fi

  [[ -n "${LUMO_FEATURES:-}" ]] && parts+=("--enable-features=$LUMO_FEATURES")
  [[ -n "${LUMO_DISABLE_FEATURES:-}" ]] && parts+=("--disable-features=$LUMO_DISABLE_FEATURES")
  if [[ -n "${LUMO_FLAGS:-}" ]]; then
    read -ra extra <<< "$LUMO_FLAGS"
    parts+=("${extra[@]}")
  fi
  (( $# )) && parts+=("$@")

  printf '%s' "${parts[*]}"
}

# The device side writes the string through `adb shell printf`, and `su -c`
# mangles nested quoting, so refuse anything that can break out of single quotes.
check() {
  local cmdline="$1"
  [[ "$cmdline" != *"'"* ]] || die "single quote in command line is not supported"
  [[ "$cmdline" != *$'\n'* ]] || die "newline in command line is not supported"
}

cmd_compose() { local c; c="$(compose "$@")"; check "$c"; printf '%s\n' "$c"; }

cmd_push() {
  need_device
  local cmdline; cmdline="$(compose "$@")"
  check "$cmdline"
  step "write $CMDLINE_PATH"
  # Written as the shell user: /data/local/tmp is shell-writable, and going
  # through `su -c` mangles the embedded newline/quoting.
  D shell "printf '%s\n' '$cmdline' > $CMDLINE_PATH; chmod 644 $CMDLINE_PATH"
  DR "am set-debug-app --persistent $PRODUCT_PKG" || warn "am set-debug-app failed"
  log "command line: $cmdline"
  # Flags from shared storage would let any app inject --load-extension, so the
  # legacy location is always cleared.
  D shell "rm -f /sdcard/Android/data/$PRODUCT_PKG/files/chrome-command-line" 2>/dev/null || true
}

cmd_show() {
  need_device
  log "path: $CMDLINE_PATH"
  D shell "cat $CMDLINE_PATH 2>/dev/null || echo '(absent)'" | sed 's/^/  /'
}

cmd_clear() {
  need_device
  D shell "rm -f $CMDLINE_PATH"
  DR "am clear-debug-app" || warn "am clear-debug-app failed"
  log "cleared $CMDLINE_PATH (browser now runs upstream defaults)"
}

cmd_presets() { printf '%s\n' "$PRESETS"; printf '\n用法: LUMO_DISABLE_FEATURES=EnableAndroidSidePanel scripts/chromium/flags.sh push\n'; }

case "${1:-compose}" in
  compose)  shift || true; cmd_compose "$@" ;;
  push)     shift || true; cmd_push "$@" ;;
  show)     cmd_show ;;
  clear)    cmd_clear ;;
  presets)  cmd_presets ;;
  *) die "usage: flags.sh [compose|push|show|clear|presets] [extra flags...]" ;;
esac
