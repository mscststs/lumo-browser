# 文档索引

收录原则：**只写目标、约束、结构**。状态、进度、验证结论、排查过程都不进文档——
它们属于 `artifacts/`（gitignored）、提交正文和 issue。

| 文档 | 类型 | 内容 |
|---|---|---|
| [01-architecture.md](01-architecture.md) | 结构 | 平台参数、上游扩展系统位置、扩展装载、构建流水线、品牌化、依赖获取的约束 |
| [02-capabilities.md](02-capabilities.md) | 约束 | 支持 / 不支持的 API 边界、补丁改变的产品默认值 |
| [03-verification.md](03-verification.md) | 约束 | 验收硬门槛、证据规则、判定陷阱 |
| [04-ui-behaviour.md](04-ui-behaviour.md) | 约束 | 侧栏两形态与断点、用户脚本默认策略、入口 |
| [05-build.md](05-build.md) | 约束 | out 目录与 flavor、GN 参数、配置 b 的限制、改动预算、缓存、签名 |
| [adr/](adr/README.md) | 决策 | 路线选择、补丁集而非 fork、dev 密钥入库 |

仓库级约束：`AGENTS.md`（工作流与禁止项）、`SECURITY.md`（威胁模型）、
`keys/README.md`（签名边界）、`patches/README.md`（补丁规则与清单）。

## 写在别处的内容

| 内容 | 位置 |
|---|---|
| 某次验收的截图 / logcat / probe.json | `artifacts/verify/<run-id>/` |
| 一次排查的中间结论 | 提交正文；稳定后提炼成约束进 `docs/` |
| 变更历史 | `CHANGELOG.md` |
| 操作步骤 | `.agents/skills/`、`scripts/README.md`、`tools/README.md` |

## 维护规则

- 结论先行；命令可复制即用；路径与参数以代码为准（不一致时改文档）。
- 过时的约束直接改写，不留"曾经的结论"；被推翻的决策由新 ADR 取代并在旧 ADR 标注。
