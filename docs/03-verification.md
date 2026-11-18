# 验收流程（真机）

目标：用**可复现的证据**回答「lumo 与 lumo-userscript-manager 是否完整可用」，而不是凭感觉。

## 1. 一键流程

```bash
scripts/chromium/build.sh a          # 产出 artifacts/apk/lumo-a-*.apk
scripts/device/install.sh            # MIUI 上走 su pm install
scripts/device/verify.sh             # 装载 probe+lumo+userscripts，采集证据
```

`verify.sh` 产出 `artifacts/verify/<run-id>/`：

| 文件 | 内容 |
|---|---|
| `screen-01-home.png` | 启动后的首页 |
| `screen-02-extensions.png` | `chrome://extensions`（经溢出菜单进入） |
| `ui-0*.xml` | uiautomator 层级（判定的机器可读来源） |
| `extensions-strings.txt` | 扩展页所有文本（名字/描述；SW 标签不在 a11y 树里，见 §2.1） |
| `probe.json` | 能力探针 30 项结果（经 CDP 从探针 SW 的 `chrome.storage` 读取，`{meta, results}`） |
| `probe-dump.log` | 探针导出诊断（SW 休眠时会被 `probe.html` 唤醒） |
| `cdp-targets.txt` | CDP 目标快照（含 `service_worker` 数量，仅作参考） |
| `logcat.txt` | 全量日志 |
| `summary.txt` | 本次结论摘要 |

## 2. 判定口径

### 2.1 必须全过的硬门槛

| ID | 判定 | 证据 |
|---|---|---|
| `ext_installed` | 扩展页出现 `Lumo`、`Lumo 用户脚本管理器`、`Lumo MV3 Probe` 三个条目 | `extensions-strings.txt` |
| `sw_running` | 探针 SW 实际执行过（`probe.json` 的 `meta.runAt` 存在且 results 非空）；CDP `service_worker` 数量作为参考（MV3 worker 会空闲退出） | `probe.json`、`cdp-targets.txt` |
| `probe_pass` | 30 项中 `pass/total ≥ 90%`；失败项必须能在下表的“环境限制”里解释 | `probe.json` |
| `scripting` | `scripting.executeScript` 在普通网页上 ok（不在 `chrome://` 上判定） | `probe.json` |
| `sidepanel` | `sidePanel.getOptions/setOptions` ok 且 UI 能打开面板 | probe + 截图 |
| `userscripts` | `userScripts.getScripts/register` ok（需在设置里打开用户脚本开关） | probe |
| `content_script` | 普通页面上 `window.__lumoProbe.world === 'isolated'` | testpage 截图 / probe detail |
| `sidepanel_render` | 侧栏能打开且 DOM 有内容（`sidepanel-strings.txt` 非空） | `ui-03-sidepanel.xml` |
| `close_panel` | 关闭侧栏后浏览器进程仍存活（`close_panel=ok`） | `close-panel.txt` |

**环境限制（可在报告里解释，不算产品缺陷）**：`tabs.captureVisibleTab` 依赖 `activeTab` 授予；
探针为自动化运行、未点击扩展动作时可能失败。`scripting.executeScript` 在 `chrome://`、
扩展页、Web Store 上不可注入——`tools/probe-dump.py --run` 会先把一个 http(s) 标签页带到前台。

### 2.2 两个参考扩展的"完整可用"

`lumo`（AI 侧栏）：
1. 扩展页 SW 正常；
2. 侧栏能在手机上打开（竖屏底部面板/横屏右侧），`sidepanel.html` 真实渲染；
3. 侧栏内能读取当前标签页内容（`chrome.scripting`/`tabs`）；
4. 设置页（options）能打开。

`lumo-userscript-manager`：
1. SW 正常；
2. `chrome.userScripts` 注册成功（开关打开后）；
3. 在测试页上注册的脚本能执行并回传结果；
4. popup/options 可交互。

## 3. 失败排查顺序

1. `logcat.txt` 里搜 `cr_CommandLine`（flags 是否生效）、`Failed to load extension`、`PROBE_JSON`。
2. `extensions-strings.txt` 里看扩展是否在列表、SW 状态。
3. `chrome://extensions` 的错误按钮（有则截图）。
4. 代码级：对照 `src/chrome/browser/ui/android/...` 与本文档 §2 的上游 wiring。
5. 只有在上述都排除后，才考虑加 patch。

## 4. 已知的判定陷阱

- **`--load-extension` 必须逗号分隔**；重复 flag 只生效最后一个。
- 探针首次运行的活动页可能是 `chrome://extensions`，`scripting.executeScript` 会因不可注入而失败——这是环境问题，需在普通网页复测。
- MIUI 上 `/data/local/chrome-command-line` 不可写；用 `/data/local/tmp/` + `am set-debug-app`，或我们 patch 过的 app 外部目录路径。
- 扩展载荷放在 app 外部目录（`/sdcard/Android/data/<pkg>/files/ext`），不要放 `/data/data`（SELinux 拒绝）。
