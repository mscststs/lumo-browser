# 验收：MV3 能力探针

本目录是**机器可读验收清单 + 静态检查**；探针扩展本体在
[`../probe-extension/`](../probe-extension/)。两者配合，用真机证据回答一个问题：
**`../lumo` 与 `../lumo-userscript-manager` 依赖的 `chrome.*` API，在自构建 Android Chromium 上哪些真的可用。**

```
tools/
├── probe-extension/        零依赖静态扩展（adb push 即可，无需构建）
└── verify/
    ├── manifest.json       验收项清单（weight 合计 100，阈值 90），每条写明证据口径
    ├── check-static.sh     纯静态检查（node --check / json / CSP / 外链 / weight / SW 冒烟）
    ├── sw-harness.js       Node + 假 chrome.* 表面跑一遍 sw.js（非浏览器测试）
    ├── check-repo.sh       仓库卫生（脚本语法/补丁编号/文档链接/skills，CI 使用）
    └── README.md           本文件
```

## 0. 静态检查（不需要设备）

```bash
bash tools/verify/check-static.sh
```

覆盖：所有 JS 过 `node --check`、两个 manifest 过 `python3 -m json.tool`、
HTML/CSS 无外链与内联脚本、无 `eval`/`new Function`、manifest 关键字段、
verify 清单条目齐全且 weight 合计 100，最后用 Node + 假 `chrome.*` 表面
跑一遍 `sw.js`（`sw-harness.js`，验证全部探针项都产出、消息路径可用、
失败项不会拖垮整轮探针）。

```bash
node tools/verify/sw-harness.js tools/probe-extension/sw.js   # 单独跑冒烟
```

> 冒烟只验证 API **形状**（promise/callback、事件对象）和代码路径，
> **不能**替代真机行为验证。

> SW 只能在浏览器里跑；`python3 -m http.server` 无法验证 service worker。
> 因此本目录**只做静态正确性**，能力判定必须上真机。

## 1. 把探针推到真机

```bash
RUN=artifacts/verify/$(date +%Y%m%d-%H%M%S)
mkdir -p "$RUN"

adb push tools/probe-extension /data/local/tmp/lumo-probe
adb shell chmod -R 755 /data/local/tmp/lumo-probe
```

### 1.1 用 `--load-extension` 启动（root）

Chromium Android 从 `/data/local/tmp/chrome-command-line` 读取启动参数；
文件必须对 app 可读（否则被静默忽略）。

```bash
adb shell 'echo "chrome --load-extension=/data/local/tmp/lumo-probe --disable-fre --no-default-browser-check" \
  > /data/local/tmp/chrome-command-line'
adb shell chmod 644 /data/local/tmp/chrome-command-line
# Magisk / Android 11 上必要时修正 SELinux 标签，不要用 setenforce 0
adb shell su -c 'restorecon -v /data/local/tmp/chrome-command-line || true'

# 验证参数确实被读取
adb shell 'cat /data/local/tmp/chrome-command-line'
```

- 包名以实际构建产物为准（如 `org.chromium.chrome` / 自建包名）。
- 非 root 的官方 Chrome **不支持** `--load-extension`，只能走 `chrome://extensions`
  的开发者模式「加载已解压的扩展程序」（需要文件选择器）。
- `--load-extension` 只在**本次启动**生效；改完参数必须 `adb shell am force-stop <pkg>` 再启动。
- 启动：`adb shell monkey -p <pkg> -c android.intent.category.LAUNCHER 1`。

### 1.2 确认装载

```bash
adb exec-out screencap -p > "$RUN/extensions.png"   # 手动打开 chrome://extensions
adb logcat -d -v threadtime | grep -Ei 'chromium|cr_' > "$RUN/logcat.txt"
```

`chrome://extensions` 里应看到 **Lumo MV3 Probe 0.1.0**，状态 enabled，无红色错误。
找不到时先怀疑 §5.1。

## 2. 采集证据（按顺序做一次即可）

| 步骤 | 操作 | 产出 |
|---|---|---|
| 1 | `chrome://extensions` 截图 | `extensions.png` |
| 2 | 任意 http(s) 页面在前台，打开扩展选项页（probe.html） | `options.png` |
| 3 | 点「重新运行」，等统计出现，点「导出 JSON」 | 手机下载目录 `probe-result.json` → `adb pull /sdcard/Download/probe-result.json "$RUN/"` |
| 4 | 点 toolbar 图标（popup）截图 | `popup.png` |
| 5 | 打开侧栏（side panel），截图并点 Ping | `sidepanel.png` + `sidepanel-ping.json` |
| 6 | 网页上长按，确认「Lumo Probe」菜单项 | `contextmenu.png` |
| 7 | 用 http 提供 testpage（见下），跑三个按钮 | `testpage.png` + `dnr.json` |
| 8 | 触发一次通知（探针已含），通知栏截图 | `notification.png` |
| 9 | 空闲 30s 后回到 probe.html 再点「重新运行」，对比 `meta.runAt` | `probe-result-wakeup.json` |

testpage 必须通过 `http(s)` 打开，content script 才会注入：

```bash
# PC 上起服务，手机访问 http://<PC-LAN-IP>:8000/testpage.html
python3 -m http.server 8000 --directory tools/probe-extension
```

`file://` 打开需要扩展详情页里开启「允许访问文件网址」，默认关闭，容易误判。

探针 JSON 结构：

```jsonc
{
  "meta":    { "trigger": "boot|onInstalled|message", "runAt": 1730000000000,
               "durationMs": 412, "pass": 20, "fail": 4, "total": 24, "ua": "…" },
  "results": [ { "api": "scripting.executeScript", "ok": true,
                 "detail": "{\"title\":\"…\",\"isolatedMarker\":true}", "error": null } ]
}
```

`ok` 的语义是**能力真的可用**，不是「探针跑完了」。因此 `offscreen` / `debugger`
两项在默认 manifest 下预期为 `false`（未声明对应权限），这是故意留的对照组。

## 3. 判定顺序

按依赖从下往上判，前一项失败会让后一项无意义：

1. **装载层**：`ext_installed` → `sw_running`
2. **基础 API**：`storage_rw` → `alarms` → `tabs_query` → `cookies`
3. **注入层**：`scripting_execute` → `content_script_isolated` → `runtime_messaging`
4. **网络层**：`dnr_dynamic_rules` → `dnr_block_effective` → `webnavigation_events`
5. **UI 层**：`action_badge` → `popup_page` → `options_page` → `contextmenus`
6. **扩展核心**：`user_scripts_api` → `side_panel_open` → `side_panel_interactive`
7. **稳定性**：`service_worker_wakeup`
8. **通知**：`notifications`

判定规则：按 `tools/verify/manifest.json` 的 `weight` 加权，`>= pass_threshold (90)` 视为
「可用基线」，同时要求第 1、3、6 组**全绿**——它们是 `../lumo` 的硬依赖，权重不能替代。
任一条目失败 → 在 `artifacts/verify/<run-id>/` 留证据 + 根因，不要只记「失败」。

## 4. 每项对应的探针输出

| verify id | probe-result.json 里的 api |
|---|---|
| `sw_running` | `meta.runAt` + 任意 `results` |
| `storage_rw` | `storage.local set+get` / `storage.session set+get` / `storage.sync set+get` |
| `alarms` | `alarms.create+getAll` |
| `notifications` | `notifications.create` |
| `tabs_query` | `tabs.query(active)` |
| `scripting_execute` | `scripting.executeScript` |
| `content_script_isolated` | `scripting.executeScript` 的 `isolatedMarker` + `probe:content:last` + testpage |
| `runtime_messaging` | `meta.trigger == "message"` + sidepanel/testpage ping |
| `dnr_dynamic_rules` | `declarativeNetRequest.dynamicRules` |
| `dnr_block_effective` | testpage「导航探测」/ `chrome://net-export` / logcat |
| `cookies` | `cookies.getAll` |
| `webnavigation_events` | `webNavigation.events`（committed 计数） |
| `contextmenus` | `contextMenus.create` |
| `action_badge` | `action.setBadgeText/setIcon` + 截图 |
| `user_scripts_api` | `userScripts.getScripts` / `userScripts.register` |
| `side_panel_open` | `sidePanel.getOptions/setOptions` + 截图 |
| `side_panel_interactive` | 侧栏内 visibilityState + ping 返回 |
| `options_page` | 截图 |
| `popup_page` | 截图 |
| `service_worker_wakeup` | 两次 `meta.runAt` 对比 + logcat |

## 5. 失败排查路径

### 5.1 扩展没出现在 chrome://extensions

```bash
adb shell 'cat /data/local/tmp/chrome-command-line'     # 参数在不在
adb shell 'ls -lZ /data/local/tmp/lumo-probe'           # 权限/标签
adb logcat -d | grep -Ei 'command.?line|load-extension|Extension.*(error|fail)'
```

- 参数文件对 app 不可读 → 整行被忽略（无报错）。
- `enable_extensions_core` 为 false（配置 `a` 的某些组合）→ 扩展系统根本没编译。
- manifest 解析失败 → logcat 有 `Manifest is not valid JSON` / `Failed to load extension`。

### 5.2 logcat 过滤

```bash
adb logcat -d -v threadtime | grep -Ei 'chromium|cr_'                # 全局
adb logcat -d -v threadtime | grep -Ei 'Extension|extensions::'      # 扩展装载
adb logcat -d -v threadtime | grep -Ei 'service.?worker|ServiceWorker' # SW 生命周期
adb logcat -d -v threadtime | grep -Ei 'declarativeNetRequest|DNR|Ruleset' # DNR
adb logcat -d -v threadtime | grep -Ei 'userScripts|UserScript'      # userScripts
```

### 5.3 逐项经验猜测

| 现象 | 优先怀疑 | 查什么 |
|---|---|---|
| `userScripts` 两项都 false，error 含 "not available" | 用户开关未开 / developer mode 未开 / `userScripts` 权限或 `extensions_features` 关闭 | `chrome://extensions` 开发者模式、`_permission_features.json` 中 `userScripts` 平台项、logcat `UserScript` |
| `sidePanel.setOptions` ok 但侧栏打不开 | phone 形态没有扩展容器（`toolbar_phone.xml` 零扩展引用）；或 side panel 需要用户手势 | 是否 tablet/桌面形态；`ExtensionSidePanelCoordinatorAndroid` 日志 |
| `webNavigation.events` 为 0 | 事件在 Android 未接线 / SW 被频繁终止导致计数清零 | 连续导航后立刻重跑；`chrome://serviceworker-internals` |
| `notifications.create` 失败 | Android 13+ `POST_NOTIFICATIONS` 被拒 / 缺少通知渠道 | 系统设置里本应用通知权限；logcat `Notification` |
| `dnr_block_effective` timeout | `webNavigation.onErrorOccurred` 没回调（不是 DNR 失败） | 先用 §5.4 的 net-export 交叉验证，再判定 DNR 本身 |
| `scripting.executeScript` 失败且 detail 提 scheme | 活动页是 `chrome://` / 新标签页 / 无标签 | 先打开一个 http(s) 页面再跑 |
| `content_script_isolated` 失败 | `file://` 未开文件访问 / 页面是 `chrome-extension://` | 用 http 提供的 testpage |
| `service_worker_wakeup` 失败 | SW 被杀后事件未重新派发 / 扩展被禁用 | logcat 看 SW start/stop；`chrome://serviceworker-internals` |
| 探针整体不返回 | SW 启动即崩溃 | `adb logcat | grep -i 'Uncaught\\|service worker'` |

### 5.4 DNR 的独立交叉验证

`testpage` 的 fetch 无法区分「被 block」与「CORS 失败」，主证据用导航探测
（`webNavigation.onErrorOccurred` 收到 `net::ERR_BLOCKED_BY_CLIENT`）。仍不确定时：

- 手动打开 `https://example.com/blocked-by-dnr`，应显示 `ERR_BLOCKED_BY_CLIENT`；
- 或 `chrome://net-export` 抓 30s 日志，在 `netlog` 里搜该 URL 的 `BLOCKED_BY_CLIENT`。

## 6. 已知局限

- 探针每个 SW 唤醒都会跑一次（这是 `service_worker_wakeup` 的证据来源），
  日志只保留最近 5 份 `probe:<ts>`，避免无限增长。
- `offscreen` / `debugger` 未在 manifest 声明权限，探针只验证「是否存在」；
  需要时另建 manifest 变体，不要在探针里偷偷加权限。
- 探针**不修改** DNR 以外的持久状态；`contextMenus` 每次先 `removeAll` 再创建，幂等。
- 侧栏行为高度依赖设备形态（phone vs tablet），证据里必须写清设备与视口。
