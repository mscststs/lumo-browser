# 文档索引

按“我现在要做什么”组织，而不是按文件编号。所有文档均为简体中文，命令可直接复制。

## 我想构建 / 迭代

| 文档 | 内容 |
|---|---|
| [09-build-iteration.md](09-build-iteration.md) | **先读这个**：构建流水线、实测成本（C++ 25 s / Java 2 min / 全量 2–4 h）、三层迭代模型、运行时开关、内核缓存、签名策略、反模式 |
| [01-architecture.md](01-architecture.md) | 架构事实：上游扩展 UI 现状、无 googlesource git 的依赖链、扩展装载机制、构建流水线 |
| [../CONTRIBUTING.md](../CONTRIBUTING.md) | 环境要求、首次搭建、补丁工作流、提交规范、PR 清单 |
| [../scripts/README.md](../scripts/README.md) | 所有脚本的一句话职责与调用顺序 |
| [../Makefile](../Makefile) | `make help` 目标速查 |

## 我想验收 / 排障

| 文档 | 内容 |
|---|---|
| [03-verification.md](03-verification.md) | 一键验收流程、7 条硬门槛、失败排查顺序、判定陷阱 |
| [06-status.md](06-status.md) | 当前状态与每条结论的证据路径 |
| [07-capability-matrix.md](07-capability-matrix.md) | MV3 30 项探针结果 + 明确不支持清单 |
| [05-gpu-notes.md](05-gpu-notes.md) | GPU/ANGLE 崩溃与 ES2 回退的排查记录 |
| [../tools/verify/README.md](../tools/verify/README.md) | 探针的装载与手动运行方式（含不用 root 的路径） |
| [../SECURITY.md](../SECURITY.md) | 威胁模型、签名边界、密钥泄露响应 |

## 我想理解设计

| 文档 | 内容 |
|---|---|
| [00-strategy-and-start.md](00-strategy-and-start.md) | 起点分析：调研报告复核、路线选择（C）、缺口清单 |
| [04-sidepanel-and-userscripts.md](04-sidepanel-and-userscripts.md) | 手机侧栏两形态（底部抽屉 / 并排可调宽）与用户脚本开关的设计 |
| [08-security-and-hardening.md](08-security-and-hardening.md) | 安全决策：命令行通道、扩展载荷目录、userScripts 默认值、侧栏生命周期 |
| [02-baseline-titanium.md](02-baseline-titanium.md) | Titanium v157 参照基线（只作问题清单，不复制 GPL 代码） |
| [adr/](adr/README.md) | 三个关键决策记录：路线、补丁集而非 fork、dev 签名密钥入库 |

## 我想改代码 / 补丁 / agent 行为

| 文档 | 内容 |
|---|---|
| [../AGENTS.md](../AGENTS.md) | 不可协商约束、目录、命令、DoD、禁止事项 |
| [../.agents/skills/](../.agents/skills/) | `chromium-android-build`、`chromium-patch-set`、`device-verification` 三个 skill |
| [../patches/README.md](../patches/README.md) | 补丁规则、状态表、编号缺口说明、新增补丁步骤 |
| [../keys/README.md](../keys/README.md) | dev 签名密钥的公开声明与操作 |

## 阅读顺序建议

1. 新人：`README.md` → `docs/09` → `docs/01` → `scripts/README.md`
2. 要改内核：`docs/09` §3 → `patches/README.md` → 对应 skill
3. 要改产品体验：`docs/04` → 扩展仓库 → `docs/03`（验收）
4. 要接设备：`docs/03` → `tools/verify/README.md` → `scripts/device/verify.sh`

## 维护约定

- 每篇文档开头写**日期 / 结论先行**；结论必须附证据路径（源码行号、截图、命令输出）。
- 命令改动后同步文档；文档与脚本不一致时，以脚本为准并立刻改文档。
- 历史决策不改写：过时的结论标注「已过时（日期）」并链接新结论，保留推理链。
