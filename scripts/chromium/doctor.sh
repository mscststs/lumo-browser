#!/usr/bin/env bash
# 环境预检：源码 / 工具链 / 设备 / 签名 / 磁盘。
#
#   scripts/chromium/doctor.sh            # 只读检查，全部通过返回 0
#   scripts/chromium/doctor.sh --strict   # 把 WARN 也当作失败
#
# 设计原则：只读（不改任何文件）、快速（<5 s）、无设备也能跑（设备项算 WARN）。
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

STRICT=0
[[ "${1:-}" == "--strict" ]] && STRICT=1

FAILS=0
WARNS=0

pass() { printf '  \033[32mok\033[0m   %s\n' "$*"; }
warn() { printf '  \033[33mwarn\033[0m %s\n' "$*"; WARNS=$((WARNS + 1)); }
fail() { printf '  \033[31mfail\033[0m %s\n' "$*"; FAILS=$((FAILS + 1)); }

section() { printf '\n\033[36m== %s ==\033[0m\n' "$*"; }

# --- host -------------------------------------------------------------------
section "主机"
pass "$(uname -srm)"
CPUS="$(nproc)"
if (( CPUS >= 8 )); then pass "CPU ${CPUS} 核"; else warn "CPU 只有 ${CPUS} 核（官方建议 ≥12，链接会慢）"; fi

MEM_GB="$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)"
if (( MEM_GB >= 32 )); then pass "内存 ${MEM_GB} GB"; else warn "内存 ${MEM_GB} GB（全量构建建议 ≥32 GB）"; fi

FREE_GB="$(df -Pk "$HOME" | awk 'NR==2 {printf "%d", $4/1024/1024}')"
if (( FREE_GB >= 120 )); then pass "磁盘可用 ${FREE_GB} GB（$HOME）";
elif (( FREE_GB >= 60 )); then warn "磁盘可用 ${FREE_GB} GB（增量够用，全量偏紧）";
else warn "磁盘可用 ${FREE_GB} GB（建议 ≥120 GB）"; fi

# --- toolchain --------------------------------------------------------------
section "工具链"
[[ -d "$DEPOT_TOOLS" ]] && pass "depot_tools: $DEPOT_TOOLS" || fail "缺少 $DEPOT_TOOLS（fetch/depot_tools）"
for tool in gn autoninja; do
  if command -v "$tool" >/dev/null 2>&1; then pass "$tool: $(command -v "$tool")"; else fail "PATH 里没有 $tool（检查 depot_tools）"; fi
done

if [[ -d "$CHROMIUM_SRC" ]]; then
  pass "CHROMIUM_SRC: $CHROMIUM_SRC"
  if [[ -f "$CHROMIUM_SRC/chrome/VERSION" ]]; then
    VER="$(awk -F= '
      /^MAJOR=/{a=$2} /^MINOR=/{b=$2} /^BUILD=/{c=$2} /^PATCH=/{d=$2}
      END{printf "%s.%s.%s.%s", a, b, c, d}' "$CHROMIUM_SRC/chrome/VERSION")"
    pass "Chromium 版本: $VER"
  else
    fail "$CHROMIUM_SRC 不像 Chromium 源码树（缺 chrome/VERSION）"
  fi
else
  fail "缺少 $CHROMIUM_SRC（见 README「快速开始」）"
fi

CLANG="$CHROMIUM_SRC/third_party/llvm-build/Release+Asserts/bin/clang"
[[ -x "$CLANG" ]] && pass "clang: $("$CLANG" --version 2>/dev/null | head -1)" \
  || warn "clang 未就绪（scripts/chromium/toolchain.sh）"

JDK="$CHROMIUM_SRC/third_party/jdk/current/bin/java"
if [[ -x "$JDK" ]] || command -v java >/dev/null 2>&1; then
  pass "JDK: $([[ -x "$JDK" ]] && "$JDK" -version 2>&1 | head -1 || java -version 2>&1 | head -1)"
else
  warn "没有 JDK（scripts/chromium/cipd-deps.sh）"
fi

if command -v keytool >/dev/null 2>&1 || [[ -x "$CHROMIUM_SRC/third_party/jdk/current/bin/keytool" ]]; then
  pass "keytool 可用（签名）"
else
  fail "缺少 keytool（签名必须）"
fi

AAPT2="$(ls "$CHROMIUM_SRC"/third_party/android_sdk/public/build-tools/*/aapt2 2>/dev/null | tail -1 || command -v aapt2 || true)"
[[ -n "$AAPT2" && -x "$AAPT2" ]] && pass "aapt2: $AAPT2" || warn "aapt2 未找到（apk-meta.sh 需要；CIPD 依赖可能未装全）"

# --- build trees ------------------------------------------------------------
section "构建树"
if [[ -d "$CHROMIUM_SRC/out" ]]; then
  while IFS= read -r d; do
    pass "$(basename "$d"): $(du -sh "$d" 2>/dev/null | cut -f1)"
  done < <(find "$CHROMIUM_SRC/out" -maxdepth 1 -mindepth 1 -type d ! -name '_*' | sort)
  [[ -d "$CHROMIUM_SRC/out/lumo-a" ]] || warn "还没有 FAST 构建树 out/lumo-a"
  [[ -d "$CHROMIUM_SRC/out/lumo-rel" || -d "$CHROMIUM_SRC/out/lumo-a-rel" ]] || warn "还没有 official 构建树"
else
  warn "没有 $CHROMIUM_SRC/out（首次构建会是全量）"
fi

# --- patches / key ----------------------------------------------------------
section "补丁与签名"
shopt -s nullglob
PATCHES=( "$REPO_ROOT"/patches/[0-9][0-9][0-9][0-9]-*.patch )
shopt -u nullglob
pass "补丁: ${#PATCHES[@]} 个"
if [[ -d "$CHROMIUM_SRC/.lumo-patches" ]]; then
  STAMPS="$(find "$CHROMIUM_SRC/.lumo-patches" -name '*.stamp' | wc -l)"
  pass "已应用 stamp: ${STAMPS} 个"
else
  warn "暂无 .lumo-patches（尚未在本树应用补丁）"
fi

if [[ -f "$LUMO_KEY_FILE" ]]; then
  if KEY_OUT="$("$REPO_ROOT/scripts/chromium/keys.sh" status 2>&1)"; then
    pass "dev key: $(printf '%s\n' "$KEY_OUT" | grep -o 'SHA256:.*' | cut -c1-40)…"
  else
    warn "dev key 存在但无法读取（见 keys/README.md）"
  fi
else
  fail "缺少 $LUMO_KEY_FILE"
fi

# --- device -----------------------------------------------------------------
section "设备"
if command -v adb >/dev/null 2>&1; then
  COUNT="$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device"' | wc -l)"
  if (( COUNT > 0 )); then
    pass "adb 设备: $COUNT 台（$DEVICE_SERIAL）"
    MODEL="$(D shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
    SDK="$(D shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')"
    pass "设备: $MODEL / API $SDK"
    if DR 'id' 2>/dev/null | grep -q 'uid=0'; then
      pass "root 可用（su）"
    else
      warn "su 不可用（安装/验收需要 root 或已开启调试握手）"
    fi
  else
    warn "没有在线设备（装机/验收相关命令会失败，构建不受影响）"
  fi
else
  warn "PATH 里没有 adb（ANDROID_SDK_ROOT/platform-tools）"
fi

# --- optional runtimes ------------------------------------------------------
section "可选运行时"
command -v node >/dev/null 2>&1 && pass "node $(node --version)（探针静态检查）" || warn "没有 node（tools/verify/check-static.sh 会跳过 node --check）"
python3 - <<'PY' 2>/dev/null && pass "python3 cairo（图标渲染）" || warn "python3 缺 cairo（brand.sh 渲染图标会失败）"
import cairo  # noqa: F401
PY
python3 - <<'PY' 2>/dev/null && pass "python3 websockets（lumo-e2e.sh）" || warn "python3 缺 websockets（仅 lumo-e2e.sh 需要）"
import websockets  # noqa: F401
PY

# --- summary ----------------------------------------------------------------
printf '\n'
if (( FAILS > 0 )); then
  printf '\033[31m%d 项失败\033[0m, %d 项警告\n' "$FAILS" "$WARNS"
  exit 1
fi
if (( STRICT && WARNS > 0 )); then
  printf '\033[33m0 项失败，%d 项警告（--strict 视为失败）\033[0m\n' "$WARNS"
  exit 1
fi
printf '\033[32m环境检查通过\033[0m（%d 项警告）\n' "$WARNS"
