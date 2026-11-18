# 能力边界（约束）

只列**承诺支持**、**明确不支持**，以及由补丁改变的产品默认值。逐项实测结果不落文档
（证据在 `artifacts/verify/<run-id>/`，判定口径见 [03-verification.md](03-verification.md)）。

## 1. 支持

扩展需自行声明对应权限；本仓库不代替扩展申请权限，也不放宽 MV3 权限模型。

| 组 | API |
|---|---|
| runtime | `getManifest` / `getURL` / `id` / `getPlatformInfo` |
| storage | `local` / `session` / `sync` |
| tabs | `query` / `create` / `update` / `captureVisibleTab`（需 `activeTab` 授予） |
| scripting | `executeScript`（隔离世界 / MAIN world） |
| cookies | `getAll` / `set` / `get` / `remove` |
| 网络 | `declarativeNetRequest`（含 `modifyHeaders`、动态规则）、`webRequest`（观察）、`webNavigation` |
| 扩展运行时 | service worker 生命周期、`offscreen`、`alarms`、`contextMenus`、`notifications`、`action` |
| 用户脚本 | `userScripts`（`MAIN` / `USER_SCRIPT` 世界），默认允许，见 §3 |
| UI | `sidePanel`（`getOptions`/`setOptions`/`open`）、扩展 popup / options、`tabGroups` |
| 其他 | `downloads`、`i18n`、`clipboardWrite`、`identity.launchWebAuthFlow` |

## 2. 不支持（平台限制，补丁不解决）

- `nativeMessaging`：Android 需要独立宿主进程。
- `desktopCapture` / `tabCapture`：没有对应的采集源语义。
- `devtools.*` 面板、`enterprise.*`、平台应用（`app.*`）。
- `chrome.windows` 的多窗口完整语义。

发布说明里不得把这些写成"支持"。

## 3. 由补丁改变的产品默认值

| 补丁 | 默认行为 | 运行时能否改回 |
|---|---|---|
| 0003 | `EnableAndroidSidePanel` 与手动调宽默认开启 | ✅ `LUMO_DISABLE_FEATURES=EnableAndroidSidePanel` |
| 0008 | `chrome.userScripts` 默认允许（扩展仍需声明权限，详情页开关可关） | 扩展详情页开关 |
| 0002 / 0009 / 0010 / 0011 | 手机工具栏承载点、popup 锚点、侧栏双形态与关闭路径 | 形态随窗口宽度（600dp 断点） |

改动这些默认值必须同时更新 `patches/README.md` 与验收口径。
