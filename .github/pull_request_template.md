# Pull Request

## 这个改动做了什么

<!-- 一句话；对应 issue 请写 `Closes #123` -->

## 落在哪一层（必填，见 AGENTS.md §5）

- [ ] 扩展层（不改内核）
- [ ] 运行时开关（`flags.sh`，不改内核）
- [ ] 内核补丁（`patches/NNNN-*.patch`）→ 填下面的补丁信息
- [ ] 工具/脚本/文档（无内核改动）

<details>
<summary>内核补丁信息（选“内核补丁”时填）</summary>

- 补丁文件：
- 上游缺口（为什么必须改内核）：
- 接线点（类/方法/文件）：
- 回滚/门控方式（feature / flag / 开关）：
- 编号与 `patches/README.md` 已同步：是 / 否

</details>

## 验证（缺证据视为未完成）

| 项 | 结果 |
|---|---|
| `bash tools/verify/check-repo.sh` | pass / fail |
| `scripts/chromium/build.sh a`（或 `DRY_RUN=1`） | 耗时：____ s |
| `scripts/device/verify.sh` → `summary.txt` | `GATE=OK` / 不适用 |
| 证据路径（`artifacts/verify/<run-id>/`） | |

## 文档

- [ ] 涉及流程的改动已同步 `AGENTS.md` / `docs/05-build.md` / `.agents/skills/`
- [ ] 涉及补丁的改动已同步 `patches/README.md`
- [ ] 未提交 `artifacts/`、`out/`、APK 或 Chromium 源码

## 风险与回滚

<!-- 影响面；如何回滚（关 feature / revert 补丁 / 换 APK） -->
