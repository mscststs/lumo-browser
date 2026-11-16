# AGENTS.md — Lumo Browser

Android Chromium 内核浏览器，目标是**完整运行 MV3 扩展**（一等公民：`../lumo`、`../lumo-userscript-manager`），并保持移动端原生体验。

## 0. 不可协商的约束

1. **内核只做最小侵入补丁**。上游已有的能力不重写；上游缺的用 `patches/` 里的 patch 文件补，禁止 `sed -i` 直改工作树。
2. **补丁必须可重放**：`scripts/chromium/apply-patches.sh` 能在干净 `main` 上按序 `git apply` 成功。
3. **UI 走原生移动形态**，不做桌面窗口形态的"适配"。参考 `../lumo` 的四条设计法则（渐进式隐藏 / 交互归一化 / 渐进式披露 / 物理级动效）。
4. **每次改动都要有设备证据**：截图、logcat 或 `chrome://extensions` 状态，落在 `artifacts/verify/<run-id>/`。
5. **真机验证优先**：Redmi K20 Pro / Android 11 / arm64 / root(Magisk)。模拟器只做冒烟。

## 1. 目录

```
patches/            按序应用的补丁（NNNN-*.patch），带 README 说明动机与上游 crbug
scripts/chromium/   拉取、打补丁、构建、产物归档
scripts/device/     安装、启动、截图、扩展装载、验收
tools/verify/       验收清单与判定逻辑（机器可读）
docs/               架构、构建、验收、决策记录
artifacts/          （gitignored）构建产物与验证证据
```

Chromium 源码放在 `~/chromium/src`（仓库外，避免污染 git）。

## 2. 常用命令

```bash
scripts/chromium/fetch.sh                 # 首次拉取（--nohistory，约 30GB）
scripts/chromium/apply-patches.sh         # 应用 patches/
scripts/chromium/build.sh                 # gn gen + autoninja + 归档 APK
scripts/device/install.sh                 # adb 安装（root pm install 绕过 MIUI 限制）
scripts/device/ext-install.sh             # 装载 ../lumo 与 ../lumo-userscript-manager
scripts/device/verify.sh                  # 30 项 MV3 探针 + 扩展/侧栏/关闭回归，产出证据目录
scripts/verify/lumo-e2e.sh                # Lumo 侧栏 + 本地 mock OpenAI 端到端验证
tools/cdp.py list|eval|type               # CDP：查目标 / 在扩展上下文求值 / 输入
```

## 3. 构建配置

两套配置，最终由证据选择（见 `docs/00-strategy-and-start.md` §5）：

| 配置 | args.gn | 用途 |
|---|---|---|
| `a` | `is_desktop_android=true` | 上游支持形态，基线参照 |
| `b` | `target_os="android"` + `enable_desktop_android_extensions=true` | 手机原生 UI + 扩展核心，产品目标 |

`scripts/chromium/build.sh <a\|b>` 选择；默认 `b`。

## 4. 代码风格

- Shell：`bash` + `set -euo pipefail`，函数式、幂等、可重入。
- 补丁：一个补丁只做一件事，标题写 `[area] why`，正文引用 crbug 或上游文件路径。
- 文档：简体中文；命令可复制即用。

## 5. 验收口径（Definition of Done）

以 `tools/verify/manifest.json` 为准，核心项：

- 两个扩展在 `chrome://extensions` 中为 enabled，无 manifest 警告阻断。
- SW 启动、`chrome.storage`/`alarms`/`notifications` 可用。
- `sidePanel` 能打开 `sidepanel.html` 并可交互（`../lumo` 的核心界面）。
- content script 注入成功、`scripting.executeScript` 返回结果。
- `chrome.userScripts` 注册成功（`../lumo-userscript-manager`）。
- DNR 规则生效（block/allow/redirect 至少各一条）。
- 扩展 popup / options 页面可打开且尺寸正常。
- 手机侧栏为可拖拽底部抽屉（peek/收起/展开），关闭不崩溃；宽屏为并排 + 可调宽。
- Lumo 侧栏能完成 provider 配置 → 流式回复（`scripts/verify/lumo-e2e.sh`）。

任何一项失败 → 必须定位根因（logcat + `chrome://extensions` 错误 + 上游源码），修完重跑。

## 6. 禁止

- 提交 Chromium 源码或 `out/` 到本仓库。
- 引入 GPL 代码（Titanium/其他 fork）；只参考其**问题清单**，实现自写。
- 用全局 `setenforce 0` 作为长期方案掩盖权限问题。
