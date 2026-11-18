# 贡献指南（CONTRIBUTING）

本仓库维护的是 **Chromium 的最小侵入补丁集 + 构建/验证工具链**，不是 Chromium fork。
提交前请先读完 `AGENTS.md`（不可协商约束）和 `docs/09-build-iteration.md`（迭代模型与成本）。

## 1. 环境

| 项 | 要求 | 说明 |
|---|---|---|
| 主机 | Linux x86_64，≥12 核 / ≥32 GB 内存（推荐 60 GB） | 全量构建吃内存与磁盘 |
| 磁盘 | ≥120 GB 空闲 | 源码 ~30 GB + 每个 out 目录 10–20 GB |
| Chromium 源码 | `~/chromium/src`（仓库外） | 不在本仓库内，永远不要提交 |
| 工具链 | `depot_tools`、CIPD 的 JDK/SDK/NDK/clang | 由 `scripts/chromium/*` 安装 |
| 设备 | Redmi K20 Pro / Android 11 / arm64 / root(Magisk) | 模拟器只做冒烟 |

自检：

```bash
scripts/chromium/doctor.sh          # 环境预检（源码/工具链/设备/签名/磁盘）
scripts/chromium/build.sh --help    # 每个脚本都有用法说明
```

## 2. 首次搭建

```bash
mkdir -p artifacts/src
# GCS 官方 tarball（约 5.4 GB）
curl -L -o artifacts/src/chromium-160.0.8157.0.tar.xz \
  https://commondatastorage.googleapis.com/chromium-browser-official/chromium-160.0.8157.0.tar.xz
scripts/chromium/extract.sh artifacts/src/chromium-160.0.8157.0.tar.xz
scripts/chromium/cipd-deps.sh
scripts/chromium/toolchain.sh
scripts/chromium/build.sh a           # 首次：数小时
```

`gn gen` 报缺少某个 `//third_party/...` 时，用 `scripts/chromium/fix-missing-deps.sh` /
`fetch-dep.sh` / `fetch-tree.sh` 补齐，并把结论写回 `docs/01-architecture.md`。

## 3. 日常迭代：先选层，再动手

| 改动 | 路径 | 是否编内核 |
|---|---|---|
| 产品功能（侧栏、脚本管理、拦截规则…） | 扩展仓库（`../lumo` 等）→ `scripts/device/ext-install.sh` | 否 |
| 行为/默认值/实验开关 | `scripts/chromium/flags.sh`（`--enable-features` / `--disable-features`） | 否 |
| 上游缺失的代码/挂载点 | `patches/NNNN-*.patch` + `scripts/chromium/build.sh` | 是（25 s – 2 min） |

**三问**：能做扩展吗 → 上游只是默认值不对吗 → 上游真的缺代码吗？只有第三问成立才允许新增补丁。

## 4. 新增/修改补丁

源码树来自官方 tarball，是一个**没有 commit** 的 git 仓库：`git diff` / `git checkout --` 都不可用。
用 `patchwork.sh` 记录 pristine 状态、导出补丁、再恢复工作树：

```bash
# 1) 记录即将修改的路径（文件或目录）
scripts/chromium/patchwork.sh start patches/0012-area-what.patch <path...>

# 2) 在 ~/chromium/src 里改（一个补丁只做一件事）

# 3) 导出 + 自检
scripts/chromium/patchwork.sh export
(cd ~/chromium/src && git apply --check ~/lumo-browser/patches/0012-area-what.patch)

# 4) 恢复 pristine，并按序重放全部补丁
scripts/chromium/patchwork.sh revert
scripts/chromium/patchwork.sh finish
scripts/chromium/apply-patches.sh      # 或 build.sh（会自动调用）

# 5) 更新 patches/README.md 的状态表（表里没有的补丁 = 文档债）
```

规则：

- 文件名 `NNNN-area-short-title.patch`，按序应用，编号只增不减。
- 标题行写清 **做了什么、为什么**，正文引用上游文件路径或 crbug。
- 不要包含 `index` 行以外的元数据噪音；只包含必要的 hunks。
- Java 补丁（~2 min）优先考虑能否用运行时开关替代；C++ 补丁（~25 s）成本更低。
- 结构性补丁应尽量用 `base::Feature` 门控，便于灰度与回滚。

## 5. 提交前检查

```bash
bash tools/verify/check-repo.sh        # 仓库卫生：脚本语法/补丁编号/文档链接/skills 结构
scripts/chromium/build.sh a            # 必须能构建（增量即可）
scripts/device/verify.sh               # 必须产出 GATE=OK（真机）
git status --short                     # 不应出现 artifacts/、out/、APK
```

`AGENTS.md` §5 的 Definition of Done 是硬门槛；**没有证据的改动视为未完成**。
证据统一落到 `artifacts/verify/<run-id>/`（截图、logcat、probe.json、summary.txt）。

## 6. 提交信息

采用 `<area>: <what>` 前缀风格（历史提交一致）：

```
build: out 目录按 flavor 隔离，避免 FAST 切换触发全量
patch: 0012 手机扩展工具栏支持内联 action
docs: 09 记录实测构建成本
test: verify 探针扩到 30 项
fix: 关闭侧栏时 detach 当前父容器
ci: 增加补丁编号与文档链接检查
```

要求：一行标题 ≤ 72 字符；正文说明「为什么」与验证方式（命令 + 证据路径）；
不要提交 `co-authored-by` 之类的共同作者尾注（保持提交者列表干净）。

## 7. PR 清单

- [ ] 改动落在正确的层（扩展 / flag / patch），并在 PR 里说明理由
- [ ] `bash tools/verify/check-repo.sh` 通过
- [ ] 构建通过；补丁在干净树可 `git apply`（CI 会校验编号与格式）
- [ ] 真机证据附在 `artifacts/verify/<run-id>/`，`summary.txt` 含 `GATE=OK`
- [ ] 相关文档同步：`patches/README.md`、`docs/09`、`AGENTS.md`（如涉及流程）
- [ ] 未提交 `artifacts/`、`out/`、APK、Chromium 源码

需要新增或修改 agent 工作方式时，改 `.agents/skills/` 下的 skill，并在 `AGENTS.md` 里保持指针一致。
