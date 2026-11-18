---
name: chromium-patch-set
description: Add, modify, audit or rebase the minimal Chromium patches in patches/. Use when a fix seems to need a kernel change, when deciding between a patch / a runtime feature flag / an extension, when a patch fails to apply after a Chromium bump, or when asked why a patch exists, whether it can be removed, or how it is gated.
---

# Chromium 补丁集（`patches/`）

## 0. 先过三问

| 问题 | 结论 |
|---|---|
| 能用扩展（JS）实现吗？ | 不改内核 → 去扩展仓库 |
| 上游已有代码，只是默认值/开关不对？ | 不改内核 → `scripts/chromium/flags.sh`（`--enable-features` / `--disable-features`） |
| 上游**确实没有**这段代码/挂载点？ | 才允许新增 `patches/NNNN-*.patch` |

反例（已踩过）：`0003` 只是把两个 `BASE_FEATURE` 的默认值翻成 ENABLED，本来就能用
`--enable-features=EnableAndroidSidePanel,EnableAndroidSidePanelManualResizing` 达到同样效果。
它保留的原因：命令行只在 `am set-debug-app` 握手时生效，普通用户启动读不到；编译默认值才是产品默认。
→ 这类补丁的价值是“产品默认”，但**必须同时保留运行时覆盖能力**（方便 A/B 与回滚）。

## 1. 现有补丁

| # | 文件 | 类型 | 触发/门控 | 能否运行时覆盖 |
|---|---|---|---|---|
| 0002 | `phone-extensions-toolbar` | 结构性（XML + Java 接线） | 编译期（ViewStub 存在即生效） | 否（但可用 `--disable-features` 关掉扩展 UI 整体） |
| 0003 | `enable-android-side-panel` | 默认值 | `kEnableAndroidSidePanel*` | ✅ `LUMO_DISABLE_FEATURES=EnableAndroidSidePanel` |
| 0005 | `gpu-respect-vulkan-optout` | 逻辑（尊重 flag） | 命令行 `--disable-features=Vulkan` | ✅ |
| 0006 | `gpu-es2-fallback` | 逻辑（GPU 信息收集） | 自动 | 否 |
| 0008 | `userscripts-optout` | 默认值（策略） | 扩展详情页开关 | 部分（用户可关） |
| 0009 | `popup-container-anchor` | 结构性（SlidingPopup） | 编译期 | 否 |
| 0010 | `sidepanel-bottom-sheet` | 结构性（双形态 + 手势） | 断点 600dp | 否（形态随窗口宽度） |
| 0011 | `sidepanel-close-detach` | 逻辑（生命周期） | 编译期 | 否 |

编号 0001/0004/0007 从未落地（被合并或放弃），**不要复用**这些编号。

## 2. 新增补丁的标准流程

```bash
# 1) 前提：源码树干净、补丁已应用、能构建
scripts/chromium/apply-patches.sh
scripts/chromium/build.sh a            # 先确认基线是绿的

# 2) 在源码树里改（只改必要的文件，改完立刻记下来）
cd ~/chromium/src
git status --short

# 3) 产出补丁（只包含本次改动的文件）
git diff -- chrome/browser/ui/android/... > ~/lumo-browser/patches/0012-my-fix.patch

# 4) 回滚源码树，验证可重放
git checkout -- chrome/browser/ui/android/...
cd ~/lumo-browser && scripts/chromium/apply-patches.sh

# 5) 构建 + 真机验证（见 device-verification skill）

# 6) 更新文档：patches/README.md（清单/门控）；成本规则见 docs/05-build.md
```

注意：`apply-patches.sh` 用 `.lumo-patches/<patch>.stamp` 记录已应用版本（sha256）。
**改了补丁文件内容必须让 stamp 失效**：删掉对应 stamp 文件再跑，否则会被跳过。

## 3. 补丁写法

见 `references/patch-anatomy.md`。要点：

- 一个补丁只做一件事；标题行 `--- a/path`（`git apply` 格式），正文不需要额外 header。
- 注释里写清“上游为什么没有 / 我们在哪个调用点接线 / 关联 feature”。
- 不要引入 `index` 之外的无意义改动（空白、行尾、重排）。
- 结构性补丁尽量用 `base::Feature` 包一层，方便灰度；默认值写在一处，别散落在多个文件。

## 4. 升级 Chromium 后

见 `references/rebase-playbook.md`。要点：

1. 新 tarball → 新 out 目录（不要复用旧 out）。
2. 逐条 `git apply --check`，失败的重做而不是硬塞。
3. 每条补丁重新跑一次真机验证，证据路径写进提交正文（不写进 docs）。
4. 版本升级是唯一值得全量构建的时机（其余时间都在增量）。

## 5. 删除/合并补丁

删除条件（必须同时满足）：

- 上游已经实现了同样能力（引用上游 commit/文件路径）；
- 或者能力已由扩展/运行时开关完全替代，且产品默认值不再需要它；
- `patches/README.md` 与 `AGENTS.md` 的补丁数同步更新；
- 真机回归通过（`GATE=OK`）。

删除方式：删文件 + 删 `.lumo-patches/*.stamp` + 更新文档；**不要**保留空编号。

## 6. 禁止

- 在仓库里直接 `sed -i` 改 `~/chromium/src` 然后不产出补丁。
- 一个补丁里混入两个不相关的修复（rebase 时会成倍痛苦）。
- 用补丁去改“能在 `flags.sh` 里翻”的默认值（除了产品默认值本身）。
- 提交前不更新 `patches/README.md`（CI 会检查 README 覆盖）。

## 7. 参考

- `references/patch-anatomy.md`：补丁结构、注释风格、门控写法
- `references/rebase-playbook.md`：升级/失败重做流程
- 仓库内：`patches/README.md`、`docs/05-build.md` §4
