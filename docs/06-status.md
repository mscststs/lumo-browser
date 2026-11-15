# 当前状态（2026-11-16 02:20 设备时间）

## 已验证（真机 Redmi K20 Pro / Android 11 / arm64）

| 项 | 结果 | 证据 |
|---|---|---|
| 自构建 APK 安装启动 | ✅ | `artifacts/apk/lumo-a-20261115-1813.apk`（Chromium 160.0.8157.0，official，343MB） |
| GPU | ⚠️ ES2 回退运行（`patches/0006`） | logcat 无 `GPU process isn't usable` |
| 命令行装载扩展（免 root 路径） | ✅ | `cr_CommandLine ... (from /storage/emulated/0/Android/data/org.chromium.chrome/files/chrome-command-line)`（`patches/0001`） |
| 三个扩展加载 | ✅ | 扩展页：Lumo 1.0.27 / Lumo MV3 Probe 0.1.0 / Lumo 用户脚本管理器 |
| Service Worker | ✅ | 扩展页「检查视图：Service Worker」 |
| 扩展菜单（手机底部弹层） | ✅ | 站点开关 + 每扩展开关 + 固定到工具栏 + 探索 + 管理（`patches/0002`） |
| `chrome://extensions` 管理页 | ✅ | 开发者模式、加载未打包、打包、更新 |
| MV3 能力探针 | ✅ 19/24（5 项为设计内不发权限/环境限制） | `PROBE_JSON`：storage/alarms/tabs/cookies/notifications/contextMenus/webNavigation/DNR/sidePanel API/downloads/i18n/action 全通过；`userScripts` 未暴露 |
| sidePanel 后端 | ✅ 已注册（`Toggle - key: kExtension...`） | `patches/0003` 启用 feature；`patches/0007` 窄屏 overlay |
| sidePanel 打开入口 | ❌ 未接（扩展 action 点击不会打开面板） | 下一步 |

## 未完成（按优先级）

1. **sidePanel 打开入口**：扩展 action 点击 → 若 `sidePanel.getOptions().enabled` 则打开面板；扩展菜单加「打开侧栏」。
2. **`chrome.userScripts` 用户开关**：上游为显式 opt-in；需要设置项 + 扩展详情页开关，否则 `../lumo-userscript-manager` 核心功能不可用。
3. **普通网页上的 `scripting.executeScript` / content script 验证**（探针当时活动页是 chrome:// 或空白页）。
4. **品牌化**：包名 `dev.lumo.browser`、应用名/图标、默认搜索引擎/主页。
5. **工具栏 action 图标**：现在只能通过扩展菜单操作；pin 到工具栏后的图标布局需验证（`patches/0002` 已提供容器）。
6. 构建产物瘦身（去掉 ARCORE/OPENXR 等未用组件）。

## 复现命令

```bash
FAST=0 OUT_DIR=out/lumo-rel scripts/chromium/build.sh a
scripts/device/install.sh
scripts/device/run.sh            # 装扩展 + 启动 + 截图
```

## 补丁清单

| 补丁 | 作用 |
|---|---|
| 0001 | 从 app 外部目录读取 chrome 命令行（CI/自动化装载扩展） |
| 0002 | 手机扩展工具栏（容器 + ToolbarPhone 接收 coordinator + 去掉 tablet 强转） |
| 0003 | 默认启用 Android side panel feature |
| 0005 | 尊重 `--disable-features=Vulkan`（避免 WebGPU interop 强拉 Vulkan） |
| 0006 | GPU 信息收集允许 ES2 回退（Adreno/ANGLE ES3 失败不再崩溃） |
| 0007 | 窄窗口 side panel 全宽 overlay |
