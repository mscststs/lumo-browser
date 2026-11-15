# 架构与工程真相（v0.1）

本文记录**已在本机/真机验证过的事实**，不是设计愿望。每条都附证据来源。

## 1. 平台基线

| 项 | 值 | 证据 |
|---|---|---|
| 目标设备 | Redmi K20 Pro（raphael），Android 11 / API 30，arm64-v8a，Magisk root | `adb shell getprop` |
| Chromium 最低 SDK | `default_min_sdk_version = 29`（`build/config/android/config.gni:63`） | 源码 |
| 选用源码 | `chromium-160.0.8157.0.tar.xz`（GCS 官方 tarball，5.39GB） | `~/artifacts/src/` |
| JDK | CIPD 自带 `jdk-25.0.5+8`（`DEPS`），系统 JDK 无关 | `DEPS` |
| 网络约束 | `chromium.googlesource.com` 的 **git smart-HTTP 不可用**（`git ls-remote` 直接 hang 到 2 分钟超时，管道写出 1.8GB 垃圾）；GCS / CIPD / GitHub 正常 | 2026-11-15 实测 |

**结论**：构建流程不能依赖 `gclient sync` 从 googlesource 拉取。改用 GCS 官方 tarball 落地源码 + `gclient runhooks` 只拉工具链（CIPD 线路可用）。

## 2. 上游扩展 UI 现状（160.x，已核实源码）

| 能力 | 上游位置 | 状态 |
|---|---|---|
| 扩展工具栏 UI | `chrome/browser/ui/android/toolbar/extensions/`（`ExtensionsToolbarCoordinator*`、`ExtensionsMenu*`、`ExtensionActionList*`、`SitePermissionsPage*`） | 完整，**含单测** |
| 工具栏挂载点 | `ToolbarManager.java:2791` 查找 `R.id.extensions_toolbar_container_stub`；`toolbar_tablet.xml:123` 有该 ViewStub，`toolbar_phone.xml` **没有** | 手机缺承载点 |
| 分发 API | `TopToolbarCoordinator.java:615` → `ToolbarLayout.java:226`（空实现）→ `ToolbarTablet` 覆写 | 手机不生效 |
| 扩展管理页 | `chrome://extensions` WebUI | 真机可用（见 §3） |
| 侧栏 | `chrome/browser/ui/android/extensions/side_panel/{internal,stub}` + `ui/side_panel/android/side_panel_native_view_android.cc` | 已有 bridge，竖屏形态待调 |
| 扩展窗口 | `ui/android/extensions/windowing/{internal,stub}` | 已有 |
| 安装对话框 | `ui/android/extensions/.../ExtensionInstallDialogBridge` | 已有 |
| 开发者私有 API | `ExtensionDeveloperPrivateBridge` | 已有 |

`internal` / `stub` 的选择只看 `enable_extensions_core`（`chrome/android/BUILD.gn:1043-1054`），不看 `is_desktop_android`。

## 3. 真机基线（Titanium v157 参照实现，用来验证"能做到什么"）

Titanium = 上游 + 185 行 `patch.sh` + GPL overlay。装在本机设备上得到的事实：

1. **UI 是 Chrome Android 移动形态**（不是桌面形态）：底部工具栏/溢出菜单、`chrome://extensions` 移动版。
2. 溢出菜单里有「扩展程序 → 打开扩展程序菜单 / 管理扩展程序 / Visit Titanium Web Store」——扩展入口在手机上**已经可用**。
3. 开发者模式打开后出现「加载未打包的扩展程序 / 打包扩展程序 / 更新」。
4. **`--load-extension` 生效**：
   `cr_CommandLine: COMMAND-LINE FLAGS: [chrome, --load-extension=..., ...] (from /data/local/tmp/chrome-command-line)`
   条件：`am set-debug-app --persistent <pkg>` + `adb_enabled=1`。
5. 扩展载荷放在 **app 外部目录**（`/sdcard/Android/data/<pkg>/files/ext/`）可被浏览器读取；`/data/local` 与 `/data/data/<pkg>` 在 MIUI + SELinux 下不可写/不可读。
6. `../lumo-userscript-manager` **能加载并运行**（扩展页显示 ID `odinkopck...`，SW 从「无效」变「Service Worker」= 被唤醒后正常）。
7. `../lumo` **加载失败**（列表中不出现，logcat 无显式错误）→ 这是我们的第一个必须根因的兼容性 bug。

> 结论：**不需要重造扩展 UI**。v0.1 的差异点只有三类：手机工具栏承载点、竖屏 sidePanel/扩展页排版、以及像 lumo 这种「静默加载失败」的兼容性修复。

## 4. 扩展装载与自动化（CI 的骨架）

```
adb push <ext> /sdcard/Android/data/dev.lumo.browser/files/ext/<name>
adb shell "printf 'chrome --load-extension=<path1> --load-extension=<path2>' \
           > /data/local/tmp/chrome-command-line"
adb shell am set-debug-app --persistent dev.lumo.browser
```

配套 patch（`patches/`）：把 command line 文件路径扩展到 app 外部目录，去掉 `set-debug-app` 依赖，使无 root 的 CI 也能装载。同时保留 `chrome://extensions` 的「加载未打包」作为用户路径。

证据采集：`scripts/device/verify.sh` → `artifacts/verify/<run>/`
- `screen-*.png`（首页、扩展页、sidepanel、popup）
- `ui-*.xml`（uiautomator 层级，用于断言文本存在）
- `logcat.txt`（过滤 `chromium|cr_|extension`）
- `probe.json`（`tools/probe-extension` 导出的 API 能力矩阵）

## 5. 构建流水线（不依赖 googlesource git）

实际可用的流水线（每一步都在本机跑通）：

```
scripts/chromium/extract.sh        # GCS 官方 tarball(5.39GB) → ~/chromium/src（无 git）
scripts/chromium/cipd-deps.sh      # 从 DEPS 生成 CIPD 表并安装（NDK/SDK/JDK/androidx/build-tools…）
scripts/chromium/fetch-dep.sh      # 缺失的 git 依赖：googlesource +archive（单依赖，秒级）
scripts/chromium/fetch-tree.sh     # 缺失的仓库子目录：+archive/<tag>/<subdir>.tar.gz
scripts/chromium/toolchain.sh      # clang(GCS) + LASTCHANGE + gclient_args.gni 修正
scripts/chromium/apply-patches.sh  # patches/ 顺序应用
scripts/chromium/build.sh a        # gn gen + autoninja(siso) + 归档 APK
```

踩过的坑（都在脚本里固化了）：

| 坑 | 现象 | 解法 |
|---|---|---|
| `gclient sync` 不可用 | `git ls-remote` 对 chromium/src 永不返回（约 100 万 ref） | 改用 GCS tarball |
| tarball 缺少 CIPD 依赖 | NDK/JDK/`androidx`/build-tools 缺失 | `cipd-deps.sh`（表由 `tools/gen_cipd_table.py` 从 DEPS 生成） |
| CIPD 包内容自带路径前缀 | 例如 SDK 包装到 `public/platforms/android-37.2/...` | 安装根 = DEPS key；androidx/android_deps 另有 `cipd/`+`committed` 布局修正 |
| `gclient runhooks` 需要每个依赖都有 `.git` | `git diff` 在 `third_party/angle` 失败 | 用 `toolchain.sh` 代替 runhooks |
| `gclient_args.gni` 由 sync 生成 | tarball 里 `checkout_android=false` → gn 断言失败 | `toolchain.sh` 改写 |
| CIPD DNS 污染 | `chrome-infra-packages.appspot.com` 解析到伪造 IPv6 | 走代理 `LUMO_PROXY=...` |
| `--load-extension` 重复 flag | 只生效最后一个 | 逗号分隔 |

为什么默认 `a`（`is_desktop_android=true`）：真机证据 §3.1 表明它产出的是 **Chrome Android 移动 UI**，同时启用 `enable_extensions_core` 全套（含 windowing/side_panel）。配置 `b` 只是在需要"严格非 desktop-android"时才用。

## 6. 待办与已知风险

| # | 事项 | 说明 |
|---|---|---|
| 1 | lumo 静默加载失败 | 先在自构建上复现，再对比 manifest 权限与 upstream feature；必要时 patch |
| 2 | 手机工具栏扩展容器 | 加 `toolbar_phone.xml` ViewStub + `ToolbarPhone` 接线（参考 tablet 的 width consumer 模式） |
| 3 | `chrome://extensions` 视口 | 移动端 CSS/尺寸补丁（Titanium 的做法可参考，代码自写） |
| 4 | `--load-extension` 免 debug-app | patch `CommandLineInitUtil` 读 app 外部目录 |
| 5 | 构建产物体积 | 官方 arm64 APK ~340MB；后续按 ABI/资源裁剪 |
| 6 | 无 KVM | 模拟器仅冒烟；真机为唯一验收环境 |
