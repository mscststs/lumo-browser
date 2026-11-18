# 架构与依赖（结构）

只描述"东西在哪、怎么串起来"。状态、进度、验证结论不写入文档（证据在 `artifacts/`）。

## 1. 平台参数

| 项 | 值 |
|---|---|
| 目标 | `chrome_public_apk`，`target_os="android"`、`target_cpu="arm64"` |
| 最低 SDK | 29（`build/config/android/config.gni:63`） |
| 内核版本 | 见 `~/chromium/src/chrome/VERSION`（当前基线 `160.0.8157.0`） |
| 源码获取 | GCS 官方 tarball（`chromium-browser-official`），解压到 `~/chromium/src` |
| 工具链 | DEPS 中的 CIPD 包（NDK/SDK/JDK/androidx/build-tools）+ clang（GCS） |
| 验收环境 | arm64 / Android 11+ / root 真机；模拟器仅冒烟 |

## 2. 上游扩展系统位置

`internal` 与 `stub` 的择一条件只有 `enable_extensions_core`（`chrome/android/BUILD.gn:1043`），
与 `is_desktop_android` 无关。

| 能力 | 上游位置 |
|---|---|
| 扩展工具栏 UI | `chrome/browser/ui/android/toolbar/extensions/`（`ExtensionsToolbarCoordinator*`、`ExtensionsMenu*`、`ExtensionActionList*`、`SitePermissionsPage*`） |
| 工具栏挂载点 | `ToolbarManager.java:2791` 查 `R.id.extensions_toolbar_container_stub`；`toolbar_tablet.xml:123` 有，`toolbar_phone.xml` 无 |
| 分发 API | `TopToolbarCoordinator.java:615` → `ToolbarLayout.java:226`（空实现）→ `ToolbarTablet` 覆写 |
| 扩展管理页 | `chrome://extensions` WebUI |
| 侧栏 | `chrome/browser/ui/android/extensions/side_panel/{internal,stub}` + `ui/side_panel/android/side_panel_native_view_android.cc` |
| 侧栏容器 | `chrome/browser/ui/side_panel/android/java/.../SidePanelContainerCoordinator.java` |
| 扩展窗口 | `ui/android/extensions/windowing/{internal,stub}` |
| 安装对话框 | `ui/android/extensions/.../ExtensionInstallDialogBridge` |
| 开发者私有 API | `ExtensionDeveloperPrivateBridge` |

## 3. 扩展装载

```bash
adb push <ext> /sdcard/Android/data/dev.lumo.browser/files/ext/<name>
adb shell "printf 'chrome --load-extension=<a>,<b>' > /data/local/tmp/chrome-command-line"
adb shell am set-debug-app --persistent dev.lumo.browser
```

约束：

- 命令行只从 `/data/local/tmp` 读取，经 debug-app 握手生效；共享存储中的同名文件一律删除。
- `--load-extension` 只有一个值，多扩展必须逗号分隔（重复 flag 只生效最后一个）。
- 载荷目录 `/sdcard/Android/data/<pkg>/files/ext/` 是开发期机制：`/data/data` 在 MIUI + SELinux 下不可读，
  `/data/local` 权限不当；正式分发不依赖此路径。
- 唯一入口是 `scripts/chromium/flags.sh`。

## 4. 构建流水线

```
scripts/chromium/extract.sh        GCS tarball → ~/chromium/src
scripts/chromium/cipd-deps.sh      DEPS 里的 CIPD 包 → 工具链
scripts/chromium/fetch-dep.sh      缺失的 git 依赖（googlesource +archive）
scripts/chromium/fetch-tree.sh     chromium/src 的子目录（+archive/<tag>/<path>）
scripts/chromium/toolchain.sh      clang + LASTCHANGE + gclient_args.gni
scripts/chromium/apply-patches.sh  patches/ 按序 git apply（sha256 stamp）
scripts/chromium/keys.sh           dev key → $CHROMIUM_SRC/lumo-signing/
scripts/chromium/brand.sh          产品名 + 图标（内容比对后才写）
scripts/chromium/build.sh          gn gen + autoninja(siso) + 归档 APK
```

out 目录规则、GN 参数、成本与缓存见 [05-build.md](05-build.md)。

## 5. 品牌化

图标不是缩放一张 PNG：`branding/app-icon-{background,foreground}.svg` 画在 108dp 网格上，
`render-icons.py` 按 Android 安全区（正中 72dp）与各密度渲染，legacy 图标由同一场景裁剪后烘焙超椭圆圆角。
应用名 / `PRODUCT_SHORTNAME` / `chrome_public_manifest_package` 分别由 `brand.sh` 与 GN 参数设置。

## 6. 依赖获取的约束

本网络下这些路径不可用，脚本已按此设计：

| 约束 | 现象 | 替代 |
|---|---|---|
| googlesource git smart-HTTP | `git ls-remote` 对 `chromium/src` 不返回（约 100 万 ref） | GCS tarball |
| `gclient sync` | 同上，且 tarball 无每依赖 `.git` | `cipd-deps.sh` / `fetch-dep.sh` / `fetch-tree.sh` |
| `gclient runhooks` | 逐依赖 `git diff` 失败 | `toolchain.sh` |
| tarball 缺 CIPD 条目 | NDK/JDK/androidx/build-tools 缺失 | `cipd-deps.sh`（表由 `tools/gen_cipd_table.py` 从 DEPS 生成） |
| `gclient_args.gni` 由 sync 生成 | tarball 里 `checkout_android=false` → gn 断言失败 | `toolchain.sh` 改写 |
| CIPD 主机 DNS 污染 | `chrome-infra-packages.appspot.com` 解析异常 | `LUMO_PROXY=...` |
