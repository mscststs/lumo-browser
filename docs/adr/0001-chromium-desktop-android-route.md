# ADR 0001：在 Chromium 上打补丁，而不是 WebView / GeckoView / fork

- 状态：已采纳
- 日期：2026-11-15
- 相关：`docs/01-architecture.md`、`docs/02-capabilities.md`、`patches/`

## 背景

目标是在 Android 上**完整运行 MV3 扩展**（`sidePanel`、`userScripts`、DNR、`scripting`、
service worker 生命周期），同时保持手机原生体验。候选路线：

| 路线 | 能力面 | 产品形态 | 维护成本 |
|---|---|---|---|
| A. 系统 WebView 自建外壳 | 无扩展引擎，需自研 API 桥 | 完全可控 | 扩展能力永远追不上 |
| B. GeckoView | 扩展模型不同（非 MV3 兼容承诺） | 需自研 UI | 与 Chrome 扩展生态不兼容 |
| C. Chromium 自构建 + 最小补丁 | 完整 MV3（探针清单覆盖） | 上游手机 UI + 少量补丁 | 每个 Chromium 版本重放补丁 |
| D. fork 现成项目（Titanium） | 同上，但绑定他人 GPL 代码与节奏 | 不可控 | 法律与 rebase 双重风险 |

## 决策

采用 **C**：官方 Chromium tarball + `is_desktop_android=true` 的构建，
只补上游缺失的手机承载点与少量行为开关（见 `patches/`）。

## 后果

- ✅ 扩展能力与上游同步，不需要自研 MV3 引擎；30 项探针 30/30。
- ✅ 补丁集只有 8 个、可逐条审计；升级 Chromium 时按 `rebase-playbook` 重放。
- ⚠️ 构建成本高（全量 2–4 h，增量 25 s–2 min），需要 120 GB 磁盘与 12 核机器。
- ⚠️ 上游 UI 是桌面形态（`is_desktop_android`），手机形态靠补丁收敛
  （0002 工具栏、0010 侧栏双形态）。
- ⚠️ 无官方更新通道/PGO，发行需要自建流程（见 `docs/05-build.md`）。

## 替代方案

- **A（WebView）**：放弃。扩展生态是产品前提，自研桥接等于重造 MV3。
- **B（GeckoView）**：放弃。扩展 API 不兼容 Chrome 生态，`../lumo` 无法零修改运行。
- **D（Titanium）**：只作为**问题清单**参考（GPL-2.0，禁止复制代码）。

## 复核条件

若出现以下情况，重新评估：上游 Android 扩展 UI 完全稳定且手机形态可用（补丁可清零）、
或构建成本成为主要瓶颈（考虑 CI 远端构建/RBE）。
