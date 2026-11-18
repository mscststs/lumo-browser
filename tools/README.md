# tools/

测试与诊断工具。全部无第三方依赖（除 `cdp.py`/`lumo-e2e.sh` 需要 `websockets`），
也可以用 `scripts/device/*` 的封装间接调用。

## Python

| 工具 | 作用 | 典型用法 |
|---|---|---|
| `cdp.py` | 极简 Chrome DevTools Protocol 客户端 | `tools/cdp.py list` / `eval --target <url> --expr '...'` / `type --selector textarea --text hi --enter` |
| `probe-dump.py` | 通过 CDP 从探针 SW 的 `chrome.storage.local` 导出 30 项结果（比 logcat 可靠：长行会被截断） | `tools/probe-dump.py --out artifacts/probe.json` |
| `mock-openai.py` | OpenAI 兼容的本地 mock（SSE 流式回复），用于证明 Lumo 侧栏链路 | `tools/mock-openai.py --port 8765` |
| `deps_resolve.py` | 在 Chromium `DEPS` 里解析某路径对应的 git 依赖（url + revision） | `tools/deps_resolve.py ~/chromium/src third_party/xxx` |
| `gen_cipd_table.py` | 从 `DEPS` 生成 CIPD 安装表（`cipd-deps.sh` 使用） | `python3 tools/gen_cipd_table.py ~/chromium/src` |

## 扩展夹具

| 目录 | 作用 |
|---|---|
| `probe-extension/` | **30 项 MV3 能力探针**（`sidePanel`/`userScripts`/DNR/`scripting`/SW 生命周期…）；结果写到 `chrome.storage.local` 供 `probe-dump.py` 读取 |
| `userscript-test/` | 最小 `chrome.userScripts` 夹具：注册一个 USER_SCRIPT 世界脚本，在页面上渲染 `LUMO_USERSCRIPT_OK` |

两个目录都是**未打包扩展**，用 `--load-extension` 装载（`scripts/device/verify.sh` 自动做）。

## verify/

| 文件/脚本 | 作用 |
|---|---|
| `manifest.json` | 验收清单（机器可读）：30 项、权重合计 100、阈值 90 |
| `check-static.sh` | 探针扩展静态检查：`node --check`、manifest/CSP/外部资源、SW 冒烟（假 `chrome.*` 表面） |
| `check-repo.sh` | 仓库卫生：`bash -n`、`py_compile`、补丁编号/README 覆盖、Markdown 链接、skills 结构、可执行位 |
| `check_repo.py` | 上面 `check-repo.sh` 的结构检查实现（可单独运行） |
| `sw-harness.js` | `check-static.sh` 使用的假 `chrome.*` 运行时 |
| `README.md` | 探针的手动装载方式（含无 root 路径） |

## 约定

- 新增工具：Python 3.10+、标准库优先、文件头写 `Usage:`；能被 `python3 -m py_compile` 通过。
- 依赖 CDP 的工具默认端口 `9222`（`verify.sh` 的命令行已带 `--remote-debugging-port=9222`）；
  用完记得 `scripts/chromium/flags.sh clear`。
- 探针/夹具的改动会改变验收结论：同步 `tools/verify/manifest.json` 与 `docs/07-capability-matrix.md`。
