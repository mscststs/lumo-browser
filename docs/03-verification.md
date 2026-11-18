# 验收口径（约束）

判定"做完了"的规则。具体某次运行的结果不写进文档，只落 `artifacts/`。

## 1. 硬门槛（全部满足才算完成）

| ID | 判定 | 证据位置 |
|---|---|---|
| `ext_installed` | `chrome://extensions` 出现 `Lumo`、`Lumo 用户脚本管理器`、`Lumo MV3 Probe` | `extensions-strings.txt` |
| `probe_pass` | 探针 `pass/total ≥ 90%`；失败项须能用 §3 解释 | `probe.json` |
| `sw_running` | 探针 SW 实际执行过（`meta.runAt` 存在、results 非空） | `probe.json` |
| `scripting` | `scripting.executeScript` 在 http(s) 页面成功（`chrome://`、扩展页、Web Store 不算） | `probe.json` |
| `userscripts` | `userScripts.getScripts/register` 成功 | `probe.json` |
| `sidepanel_render` | 侧栏能打开且容器有内容 | `ui-03-sidepanel.xml`、`sidepanel-strings.txt` |
| `close_panel` | 关闭侧栏后浏览器进程存活 | `close-panel.txt` = `close_panel=ok` |
| `gate` | `summary.txt` 末尾 `GATE=OK` | `summary.txt` |

## 2. 证据规则

- 每次运行一个目录：`artifacts/verify/<YYYYMMDD-HHMMSS>/`（`verify.sh` 生成）。
- 文档与提交正文只写**路径**，不复述状态表；状态由证据目录表达。
- 声称"全新安装可用"必须先卸载重装再跑，并在提交正文说明。
- 模拟器结果只算冒烟；GPU、手势、侧栏形态必须在真机。

## 3. 判定陷阱

| 陷阱 | 处理 |
|---|---|
| 在 `chrome://extensions` 上测 `scripting` | 先导航到 http(s) 页面（`probe-dump.py --run` 会把 web 标签页带到前台） |
| 扩展显示「无效」就判失败 | SW 会休眠；等 5–10 s 或打开扩展页再看，探针 payload 才是准的 |
| 用扩展页文本判断 SW 状态 | a11y 树里没有 SW 标签；用 `probe.json` + CDP `service_worker` 数量（后者仅参考） |
| 用坐标点击 | 用 `text=` / `content-desc=`（`tap_text`） |
| 只测增量状态 | 卸载重装后重跑 |
| 追求"跑过为止" | 先看 `logcat.txt` 的 `Failed to load extension` / `cr_CommandLine` / `PROBE_JSON` |

## 4. 工具

```bash
scripts/device/verify.sh        # 生成证据目录与 GATE
scripts/verify/lumo-e2e.sh      # 侧栏 + 本地 mock OpenAI 端到端
tools/verify/check-static.sh    # 探针静态检查（无需设备）
tools/cdp.py list|eval|type     # CDP（需 --remote-debugging-port=9222）
tools/probe-dump.py --run       # 从探针 SW 的 storage 导出 {meta, results}
```

验收清单的机器可读版本：`tools/verify/manifest.json`。
