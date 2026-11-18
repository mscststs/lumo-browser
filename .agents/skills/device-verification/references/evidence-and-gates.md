# 证据与判定（GATE）

## 1. 目录结构

`scripts/device/verify.sh` 每次运行生成 `artifacts/verify/<YYYYMMDD-HHMMSS>/`：

| 文件 | 内容 | 判定用途 |
|---|---|---|
| `summary.txt` | 每步结论 + 最终 `GATE=OK` / `GATE=FAIL` | 唯一总判定 |
| `screen-01-home.png` … | 首页 / 扩展页 / 侧栏 / popup / testpage | 视觉证据 |
| `ui-*.xml` | `uiautomator dump` 层级 | 机器可读文本断言 |
| `extensions-strings.txt` | 扩展页全部文本 | 扩展名、`Service Worker` 状态 |
| `probe.json` | 探针导出的 30 项结果 | API 能力矩阵 |
| `logcat.txt` | 全量日志（已过滤 `chromium|cr_|extension`） | 失败根因 |
| `close-panel.txt` | `close_panel=ok` | 侧栏关闭回归 |

`scripts/verify/lumo-e2e.sh` 生成 `artifacts/verify/lumo-e2e-<ts>/`，包含
`screen-lumo-e2e.png`、`mock-openai.log`、`e2e.txt`。

## 2. 30 项探针（现行）

完整清单在 `tools/verify/manifest.json`（weight 合计 100，阈值 90）。
分组：

| 组 | 项 |
|---|---|
| runtime | getManifest / getURL / id / getPlatformInfo |
| storage | local / session / sync 读写 |
| alarms | create + getAll + clear |
| tabs | query(active)、create/update 存在性、captureVisibleTab |
| scripting | 隔离世界 / MAIN world 注入 |
| cookies | getAll / set / get / remove |
| notifications / contextMenus | create（含权限） |
| webNavigation / webRequest | 事件注册 + 回调 |
| declarativeNetRequest | 动态规则 + 实际 block 生效 |
| userScripts | getScripts / register |
| sidePanel | getOptions / setOptions |
| offscreen | createDocument + getContexts + close |
| debugger | API 存在性（不实际 attach） |
| tabGroups | group + update + query + ungroup |
| identity | launchWebAuthFlow 存在性 |
| i18n / action / downloads | 存在性与基本行为 |
| clipboardWrite | 权限 + `navigator.clipboard` |

**判定口径**：`meta.fail` 只允许「探针故意未声明权限」的项（`offscreen`/`debugger`），
其余任何 fail 都算缺口：在提交正文/issue 记录根因，并核对 `docs/02-capabilities.md` 的承诺边界是否写错。

## 3. GATE 规则

`summary.txt` 末尾必须出现：

```
GATE=OK
```

`GATE=OK` 的必要条件（`verify.sh` 内联判定）：

1. 探针 JSON 存在且 `meta.fail` 在允许集合内；
2. `extensions-strings.txt` 出现 `Lumo`、`Lumo Userscripts`、`Lumo MV3 Probe`，
   且每个都有 `Service Worker`（不是「（无效）」）；
3. 扩展页截图与侧栏截图非空（`screen-*.png` 大小 > 0）；
4. 侧栏关闭回归 `close_panel=ok`；
5. 设备在线、`pm path dev.lumo.browser` 有输出。

判定失败时不要“重跑到过为止”：先看 `logcat.txt` 的
`Failed to load extension` / `cr_CommandLine` / `PROBE_JSON`，再改代码。

## 4. 判定陷阱（真实踩过）

| 陷阱 | 正确做法 |
|---|---|
| 在 `chrome://extensions` 上测 `scripting.executeScript` | 先导航到普通 http(s) 页面 |
| 扩展显示「无效」就判定加载失败 | SW 未唤醒也会显示「无效」；等 5–10 s 或点开扩展页再看 |
| 用 `--load-extension=a --load-extension=b` | 重复 flag 只生效最后一个，必须逗号分隔（`flags.sh` 已处理） |
| 只测增量状态就宣称“全新安装正常” | 卸载重装后再跑一次，记录在 `summary.txt` |
| 用坐标点击 UI | 分辨率/DPI 不同会漂；用 `text=` / `content-desc=`（`tap_text`） |
| 忽略 `userScripts` 开关 | 补丁 0008 后默认允许，但扩展仍需声明权限；详情页可关闭 |
| 把模拟器结果当验收 | 模拟器只做冒烟，GPU/侧栏手势必须在真机 |

## 5. 证据只写进提交正文

```text
验证：scripts/device/verify.sh → artifacts/verify/20261116-130705/summary.txt (GATE=OK)
      probe 30/30，extensions-strings 3×Service Worker，close_panel=ok
      Lumo e2e: artifacts/verify/lumo-e2e-20261116-130954/screen-lumo-e2e.png
```

只写“已验证”而不给路径的改动，在 review 里视为未验证。文档（`docs/`）只记约束，不记这些结果。
