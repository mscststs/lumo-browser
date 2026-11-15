# 真机基线证据：Titanium v157（参照实现）

采集时间：2026-11-15　设备：Redmi K20 Pro / Android 11 / arm64 / Magisk
用途：这是我们**自构建之前的对照基线**。任何"我们做到了"的结论，都要和这份矩阵逐项对比。

## 1. 装载机制（已验证）

```bash
adb push <ext> /sdcard/Android/data/<pkg>/files/ext/<name>
adb shell "printf 'chrome --load-extension=%s\n' '<p1>,<p2>,<p3>' > /data/local/tmp/chrome-command-line"
adb shell su -c "am set-debug-app --persistent <pkg>"
```

关键事实（踩过的坑）：

| 事实 | 证据 |
|---|---|
| 多个扩展必须**逗号分隔**放在一个 `--load-extension` 里 | 重复写 `--load-extension=A --load-extension=B` 时只有最后一个生效（`base::CommandLine` 同名 switch 覆盖）；改成 `A,B` 后三个同时加载 |
| 命令读取路径是 `/data/local/tmp/chrome-command-line` | logcat `cr_CommandLine: COMMAND-LINE FLAGS: [...] (from /data/local/tmp/chrome-command-line)` |
| 需要 `am set-debug-app --persistent <pkg>`（或 debug 构建） | 未设置时该文件被忽略（`CommandLineInitUtil.shouldUseDebugCommandLine`） |
| 载荷目录用 app **外部**目录 | `/data/local` 与 `/data/data/<pkg>` 在 MIUI + SELinux 下 root 也写不进去 |
| `chrome://` 不能通过 intent 打开 | Titanium 打了 scheme guard；只能走 UI 菜单 |

## 2. 扩展加载结果

| 扩展 | 结果 | 证据 |
|---|---|---|
| `../lumo`（1.0.27） | ✅ 加载，SW 运行 | 扩展页显示 "Lumo / 1.0.27 / AI 驱动的浏览器侧边栏助手 / 检查视图：Service Worker" |
| `../lumo-userscript-manager`（1.0.4） | ✅ 加载，SW 可唤醒 | 同上，SW 初始显示"（无效）"，唤醒后变为 "Service Worker" |
| `tools/probe-extension`（0.1.0） | ✅ 加载并自动跑探针 | logcat `PROBE_JSON {...}` |

## 3. API 能力矩阵（探针实测，19 pass / 5 fail / 24）

通过：

`runtime.getManifest/getURL/id/getPlatformInfo`、`storage.local/session/sync`、
`alarms.create+getAll`、`tabs.query`、`tabs.create/update`（存在）、`cookies.getAll`、
`notifications.create`、`contextMenus.create`、`webNavigation.*`（事件有回调）、
`declarativeNetRequest.getDynamicRules/updateDynamicRules`、`sidePanel.getOptions/setOptions`、
`downloads.download/search`、`i18n.getMessage`、`action.setBadgeText/setIcon`

未通过（3 项是探针故意未声明权限，2 项是环境问题）：

| 项 | 原因 | 判定 |
|---|---|---|
| `scripting.executeScript` | 当时活动页是 `chrome://extensions/`，不可注入 | 环境问题，需在普通网页复测 |
| `userScripts.getScripts/register` | `chrome.userScripts` 未暴露 | **真实缺口**：需要 userScripts 权限 + 用户开关（developer mode）。Titanium 上未把开关暴露到 UI |
| `offscreen.createDocument` | manifest 未声明 `offscreen` | 探针设计（对照项） |
| `debugger.attach` | manifest 未声明 `debugger` | 探针设计（对照项） |

UA：`Chrome/157.0.0.0 Mobile`（Android 11 被识别为 `Android 10; K`，Chromium 的 UA 归并行为）。

## 4. UI 事实

| 能力 | 状态 |
|---|---|
| 溢出菜单「扩展程序 → 打开扩展程序菜单 / 管理扩展程序」 | ✅ 可用 |
| `chrome://extensions` 移动版：搜索、开发者模式、加载未打包、打包、更新 | ✅ 可用 |
| 扩展菜单列出每个扩展 + 「固定到工具栏」 | ✅ 可用 |
| 工具栏内嵌 action 图标 | 仅 tablet 布局有容器；Titanium 用改造过的工具栏在手机上显示了扩展按钮 |
| **`chrome.sidePanel` 的面板呈现** | ❌ 未实现：点击扩展 action 不会打开侧栏；没有 side panel 宿主 UI |

结论：**sidePanel 的 API 已经有了，缺的是移动端宿主 UI 与 action→panel 的联动**。这是 Lumo 浏览器 v0.1 的核心自研项（不是"把 API 打开"）。

## 5. 对我们的直接指令

1. `scripts/device/*` 已按"逗号分隔 + 外部目录 + set-debug-app"实现。
2. `patches/0001` 目标是去掉 `set-debug-app` 依赖（CI 更稳）。
3. `patches/0002` 目标：手机工具栏承载点。
4. 新补丁（v0.1 核心）：**sidePanel 手机宿主**——竖屏 bottom sheet / 横屏右侧抽屉；action 点击按 `sidePanel.getOptions().enabled` 与 `setPanelBehavior({openPanelOnActionClick})` 决定是否打开；`chrome.sidePanel.open()` 的手势校验由 UI 层授予。
5. `userScripts` 开关必须做进设置页（否则 `../lumo-userscript-manager` 的核心功能不可用）。
