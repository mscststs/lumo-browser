# Agent Skills（一线操作手册）

本目录是给 agent（和新人）用的**可执行工作手册**，与本仓库的脚本一一对应。
与 `AGENTS.md` 的分工：

- `AGENTS.md`：**约束**（什么不能做、DoD、禁止项）
- `.agents/skills/`：**操作**（怎么一步步做、失败怎么排查）

## 索引

| Skill | 什么时候读 | 对应脚本 |
|---|---|---|
| [`chromium-android-build`](skills/chromium-android-build/SKILL.md) | 取源码、构建、加速迭代、out 目录/缓存/签名问题 | `scripts/chromium/{doctor,extract,cipd-deps,toolchain,build,cache,keys}.sh` |
| [`chromium-patch-set`](skills/chromium-patch-set/SKILL.md) | 新增/修改补丁、Chromium 升级后的 rebase、判断该不该打补丁 | `patches/`、`scripts/chromium/apply-patches.sh` |
| [`device-verification`](skills/device-verification/SKILL.md) | 装机、装载扩展、真机验收、采集证据、MIUI/SELinux 排障 | `scripts/device/*`、`scripts/verify/*`、`tools/cdp.py` |

## 结构

```
.agents/skills/<name>/
├── SKILL.md          # 入口：触发条件 + 标准流程 + 禁止项
└── references/       # 细节：命令、表格、故障树（按需读，不必一次全读）
```

`SKILL.md` 的 frontmatter 必须包含 `name` 与 `description`；
`check-repo.sh` 会校验这一点，也会校验 `references/` 里的相对链接存在。

## 维护规则

- 脚本改了就改对应 skill；skill 里的命令必须能直接复制运行。
- 新经验（一次排查出来的根因）写进 `references/`，而不是塞进 `AGENTS.md`。
- 本目录的 skill 是**本仓库自研**（非外部导入），因此没有 `skills-lock.json`；
  若将来引入外部 skill，再加锁文件并在此说明来源。
