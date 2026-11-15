# MV3 能力矩阵（真机实测）

设备：Redmi K20 Pro / Android 11 / arm64 / Magisk　构建：Chromium 160.0.8157.0（Lumo，official）
探针：`tools/probe-extension`（30 项），运行方式见 `scripts/device/verify.sh`

## 1. 探针结果（30/30 通过）

| 分组 | 探针项 | 结果 | 备注 |
|---|---|---|---|
| runtime | getManifest / getURL / id / getPlatformInfo | ✅ | |
| storage | local / session / sync 读写 | ✅ | |
| alarms | create + getAll + clear | ✅ | |
| tabs | query(active) | ✅ | |
| tabs | create/update 存在性 | ✅ | 未实际开新标签 |
| scripting | executeScript（隔离世界） | ✅ | 返回页面 title + 注入标记 |
| scripting | executeScript（MAIN world） | ✅ | `{marker:42, isIsolated:false}` |
| cookies | getAll | ✅ | |
| cookies | set / get / remove | ✅ | 往返校验 |
| notifications | create（含权限） | ✅ | |
| contextMenus | create | ✅ | |
| webNavigation | 事件注册 + 回调 | ✅ | onCommitted/onCompleted |
| webRequest | onBeforeRequest + onCompleted | ✅ | 各触发 1 次 |
| declarativeNetRequest | 动态规则 add/get/remove | ✅ | |
| declarativeNetRequest | 规则实际生效（block） | ✅ | `net::ERR_BLOCKED_BY_CLIENT` |
| userScripts | getScripts / register | ✅ | 见 §2 真实执行 |
| sidePanel | getOptions / setOptions | ✅ | 面板渲染见 §3 |
| downloads | API 存在性 | ✅ | |
| i18n | getMessage/getUILanguage | ✅ | |
| action | setBadgeText / setIcon | ✅ | |
| offscreen | createDocument + getContexts + close | ✅ | reason 用 `DOM_SCRAPING` |
| debugger | API 存在性 | ✅ | 未实际 attach（避免弹提示） |
| tabGroups | group + update + query + ungroup | ✅ | |
| identity | launchWebAuthFlow 存在性 | ✅ | 未发起真实 OAuth |
| tabs | captureVisibleTab | ✅ | ~151KB JPEG |
| clipboardWrite | 权限 + navigator.clipboard | ✅ | 见 manifest 权限 |

已知不在此矩阵内的能力：`nativeMessaging`（Android 需独立宿主）、`desktopCapture`（无采集源）、
`devtools.*` 面板、平台应用（`app.*`）。这些属于平台限制，不是补丁能解决的。

## 2. 用户脚本真实执行

`tools/userscript-test` 注册一个 `USER_SCRIPT` 世界的脚本到 `https://example.com/*`，
页面渲染出 `LUMO_USERSCRIPT_OK`。证据：
`artifacts/verify/userscript-proof.png`、`artifacts/verify/sheet-page-scroll.png`。

## 3. Side panel 双形态

| 形态 | 触发条件 | 行为 | 证据 |
|---|---|---|---|
| 底部抽屉 | `screenWidthDp < 600` | peek 64dp / 收起 45% / 展开 75%，可拖拽；页面保持可见可交互；关闭不崩溃 | `sheet2-collapsed.png`、`sheet2-expanded.png`、`sheet2-peek2.png`、`closecycle-*` |
| 并排 | `screenWidthDp >= 600` | 右侧面板 + 可拖拽宽度；页面宽度不受遮挡 | `tablet-panel-2.png` |

## 4. 扩展端到端

| 扩展 | 验收 | 证据 |
|---|---|---|
| `../lumo` | 加载、SW 运行、侧栏渲染、provider 配置、**流式回复**（mock OpenAI） | `artifacts/verify/lumo-e2e-*/screen-lumo-e2e.png`、`panel-after-send.txt` |
| `../lumo-userscript-manager` | 加载、SW 运行、popup、`userScripts` 注册与执行、详情页「允许运行用户脚本」开关 | `us-popup2.png`、`userscripts-toggle.png` |
