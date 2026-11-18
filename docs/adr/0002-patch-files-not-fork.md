# ADR 0002：用有序 patch 文件维护内核差异，而不是 overlay 目录或 fork

- 状态：已采纳
- 日期：2026-11-15
- 相关：`patches/README.md`、`.agents/skills/chromium-patch-set/`、`scripts/chromium/apply-patches.sh`

## 背景

内核差异可以三种方式维护：

| 方式 | 形态 | 优点 | 缺点 |
|---|---|---|---|
| fork / 长期分支 | 完整 Chromium 仓库 | 开发直观 | 与上游合并成本随补丁数指数上升 |
| overlay 目录（Brave 风格） | 用同名文件覆盖上游 | 文件级替换清晰 | 需要构建系统支持；小改动也要整文件替换，diff 不可读 |
| 有序 patch 文件 | `NNNN-*.patch` + `git apply` | diff 可读、可逐条审计/删除、按序重放 | 上游上下文漂移时需要重做补丁 |

## 决策

采用 **有序 patch 文件**：

- 文件名 `NNNN-area-short-title.patch`，`apply-patches.sh` 按序 `git apply`。
- 用 `.lumo-patches/<patch>.stamp`（patch 文件的 sha256）记录“已应用”，避免链式 reverse-check 的误判
  （后续补丁会修改同一文件）。
- 补丁内容用 `scripts/chromium/patchwork.sh` 生成（源码树没有 commit，`git diff` 不可用）。
- 每个补丁必须在 `patches/README.md` 登记（CI 检查覆盖）。

## 后果

- ✅ 补丁量小（8 个 / 608 行），review 成本低；删补丁 = 删文件 + 删 stamp。
- ✅ 升级 Chromium 时失败点明确：`apply-patches.sh` 会在第一处失败停下，并指出补丁名。
- ⚠️ 上游代码移动会导致 hunk 漂移，需要按 `rebase-playbook.md` 重做（不鼓励手工 fuzz）。
- ⚠️ 补丁之间可能互相影响同一文件（0002/0009/0010/0011 都碰 UI 层），
  因此**必须按序应用**，且不要并行调整同一文件的两条补丁。

## 替代方案

- **overlay 目录**：放弃。需要改构建系统（`BUILD.gn` 的 sources 重定向），
  且会让“这个文件为什么和上游不同”不可见。
- **fork**：放弃。单人维护下，fork 会在 1–2 个版本周期内失去可合并性。

## 复核条件

补丁数超过 ~25 个，或同一文件被 3 条以上补丁反复修改时，考虑引入 overlay/feature 模块化。
