# AGENTS.md — Lumo Browser

Android Chromium 内核浏览器，目标是**完整运行 MV3 扩展**（一等公民：`../lumo`、
`../lumo-userscript-manager`），并保持移动端原生体验。

本文件是**硬约束与工作流**。操作细节不在正文展开，按指针读：

- 构建约束 / 成本 / 缓存 → `docs/05-build.md`
- 具体操作手册 → `.agents/skills/`（构建 / 补丁 / 真机验证）
- 验收口径 → `docs/03-verification.md` + `tools/verify/manifest.json`
- 补丁清单 → `patches/README.md`；签名边界 → `keys/README.md`、`SECURITY.md`

## 0. 不可协商的约束

1. **内核只做最小侵入补丁**。上游已有的能力不重写；上游缺的用 `patches/` 里的 patch 文件补，
   禁止 `sed -i` 直改源码树。
2. **补丁必须可重放**：`scripts/chromium/apply-patches.sh` 能在干净源码上按序 `git apply` 成功；
   新增补丁必须更新 `patches/README.md` 的清单。
3. **UI 走原生移动形态**，不做桌面窗口形态的"适配"。参考 `../lumo` 的四条设计法则
   （渐进式隐藏 / 交互归一化 / 渐进式披露 / 物理级动效）。
4. **每次改动都要有设备证据**：截图、logcat 或 `chrome://extensions` 状态，
   落在 `artifacts/verify/<run-id>/`；没有证据视为未完成。
5. **真机验证优先**：Redmi K20 Pro / Android 11 / arm64 / root(Magisk)。模拟器只做冒烟。
6. **能运行时开关的不进补丁**：行为/默认值优先走 `scripts/chromium/flags.sh`
   （`--enable-features` / `--disable-features`）；只有上游确实缺代码才新增 patch。
7. **一个 out 目录一个 flavor**：`FAST` 改变 `is_official_build`，共用目录会导致近乎全量重编
   （`out/lumo-a` = FAST，`out/lumo-rel` = official；不要手工把两者混用）。

## 1. 快速事实

| 项 | 值 |
|---|---|
| 产品名 / 包名 | Lumo / `dev.lumo.browser` |
| 内核 | Chromium `160.0.8157.0`（official，arm64，`is_desktop_android=true`） |
| 交付配置 | `a`（`is_desktop_android=true`）；`b` 不可直接编译（`docs/05-build.md` §3） |
| 源码位置 | `~/chromium/src`（仓库外）；`DEPOT_TOOLS=~/depot_tools` |
| 构建目标 | `chrome_public_apk` → `artifacts/apk/lumo-<config>-<ts>.apk`（≈343 MB） |
| 签名 | `keys/lumo-dev.jks`（公开、仅 debug）→ 可 `pm install -r` 覆盖升级 |
| 补丁数 | 8（0002/0003/0005/0006/0008/0009/0010/0011） |
| 验收门槛 | `scripts/device/verify.sh` 输出 `GATE=OK` |

## 2. 目录

```
.agents/skills/     一线操作手册（构建 / 补丁 / 真机验证），改流程时同步更新
.github/            CI（静态检查 + 仓库卫生）与 PR 模板
keys/               dev 签名密钥（故意入库，仅 debug，见 keys/README.md）
patches/            NNNN-*.patch 按序应用 + README 清单
scripts/chromium/   取源码、依赖、工具链、打补丁、构建、签名、flags、缓存、doctor
scripts/device/     安装、启动、扩展装载、验收、截图
scripts/verify/     端到端（Lumo 侧栏 + mock OpenAI）
scripts/lib/        common.sh、signing.env（共享 shell 库）
tools/              CDP、探针扩展、mock server、仓库检查
docs/               架构、验收、能力矩阵、ADR
artifacts/          （gitignored）APK、验证证据、缓存 manifest
```

## 3. 常用命令

```bash
scripts/chromium/doctor.sh                # 环境预检（源码/工具链/设备/签名/磁盘）
scripts/chromium/build.sh a               # 补丁 + 签名 + gn + siso 增量 + 归档
scripts/chromium/build.sh a --help        # （或直接看脚本头）用法与 env
scripts/chromium/flags.sh push|presets    # 运行时开关（feature flags / 扩展装载），不重编译
scripts/chromium/cache.sh manifest        # 内核身份清单（版本/args/patch sha/APK sha）
scripts/chromium/cache.sh snapshot        # 归档 out/（跨机器复用编译缓存）
scripts/chromium/keys.sh status           # dev 签名密钥信息与指纹
scripts/device/install.sh                 # adb root pm install（绕过 MIUI 限制）
scripts/device/ext-install.sh             # 装载 ../lumo 与 ../lumo-userscript-manager
scripts/device/verify.sh                  # 30 项探针 + 扩展/SW + 侧栏/关闭回归 + GATE
scripts/verify/lumo-e2e.sh                # Lumo 侧栏 + 本地 mock OpenAI 端到端
tools/cdp.py list|eval|type               # CDP：查目标 / 在扩展上下文求值 / 输入
bash tools/verify/check-repo.sh           # 仓库卫生（语法/补丁编号/文档链接/skills）
make help                                 # 以上命令的 Makefile 入口
```

## 4. 构建配置与 out 目录

| 配置 | args.gn 关键项 | 用途 | out 目录 |
|---|---|---|---|
| `a` | `is_desktop_android = true` | 上游唯一带完整扩展 UI 的 Android 形态，交付配置 | `out/lumo-a`（FAST）/ `out/lumo-rel`（official） |
| `b` | `target_os="android"` + `enable_desktop_android_extensions=true` | 手机原生 UI + 扩展核心，**实测被上游 gn 断言阻塞**（`docs/05-build.md` §3） | `out/lumo-b`（不存在；不要用 `build.sh b` 试） |

- `build.sh` 默认 `a`；`FAST=1`（默认）产非 official 包用于迭代，`FAST=0` 产 official 包用于验收。
- 切换配置或 `FAST` = 一次全量构建（数小时、+10–20 GB）。先定配置，再开始改代码。
- `DRY_RUN=1 scripts/chromium/build.sh a` 可以只看解析结果，不编译。

## 5. 迭代模型

三问：能做扩展吗 → 上游只是默认值不对吗 → 上游真的缺代码吗。只有第三问成立才进 `patches/`。
out 目录、成本量级、缓存与签名规则见 `docs/05-build.md`。

## 6. 补丁规则

- 文件名 `NNNN-area-short-title.patch`，按序应用，编号只增不减。
- 一个补丁只做一件事；标题行写清 what/why，正文引用上游文件路径或 crbug。
- 生成方式：`scripts/chromium/patchwork.sh start/export/revert`（源码树没有 commit，`git diff` 不可用）。
- 结构性补丁尽量用 `base::Feature` 门控；默认值翻转类（如 0003）必须能用命令行覆盖做回归。
- 新增/修改补丁必须同步 `patches/README.md`（清单 + 门控 + 动机）。
- CI 会检查补丁编号连续性、`--- a/` 头、README 覆盖；本机用 `tools/verify/check-repo.sh`。

## 7. 验收口径

硬门槛：`scripts/device/verify.sh` 输出 `GATE=OK`。判定项、陷阱与证据规则见
`docs/03-verification.md` + `tools/verify/manifest.json`。
证据只落 `artifacts/verify/<run-id>/`；文档与提交正文只引用路径，不复述状态。

## 8. 代码风格

- Shell：`bash` + `set -euo pipefail`（`fix-missing-deps.sh` 例外，脚本内有注释说明原因）、
  函数式、幂等、可重入；共享逻辑进 `scripts/lib/common.sh`，不要复制粘贴。
- Python：3.10+，标准库优先；新增工具需能被 `python3 -m py_compile` 通过。
- 补丁：见 §6。
- 文档：简体中文、结论先行、命令可复制即用；命令改了要同步文档。
- 提交：`<area>: <what>`（build/patch/docs/test/fix/ci），正文写“为什么 + 验证方式”。

## 9. 安全与签名

- dev key 公开入库（`keys/README.md`）：可覆盖升级，但**不代表来源可信**；正式分发另建 release key。
- 命令行只走 `am set-debug-app` 握手 + `/data/local/tmp`；共享存储里的同名文件由 `flags.sh` 主动删除。
- 不改 Chromium 沙箱/站点隔离/权限模型；补丁范围见 `SECURITY.md` §2。
- 验证用的 `--remote-debugging-port=9222` 结束后执行 `scripts/chromium/flags.sh clear`。

## 10. 禁止

- 提交 Chromium 源码、`out/`、`artifacts/`、APK。
- 引入 GPL 代码（Titanium 等 fork）；只参考其**问题清单**，实现自写。
- 用全局 `setenforce 0` 作为长期方案掩盖权限问题。
- 为了“快”把 `FAST=0`/`FAST=1` 塞进同一个 out 目录。
- 在文档里把未验证的能力写成“支持”（未构建的配置、平台限制项）。

## 11. Agent 工作流

1. **先定位层**：扩展 / 运行时开关 / 内核补丁（§5 三问）。
2. **读对应 skill**：`.agents/skills/chromium-android-build`（构建与缓存）、
   `.agents/skills/chromium-patch-set`（补丁）、`.agents/skills/device-verification`（真机）。
3. **改完自检**：`bash tools/verify/check-repo.sh` + `scripts/chromium/build.sh a`
   （或 `DRY_RUN=1` 验证解析）；真机改动再跑 `scripts/device/verify.sh`。
4. **记录证据**：命令、耗时、证据路径（`artifacts/...`）写进提交正文；不写进文档。
5. **同步文档**：改流程 → 改 `AGENTS.md`/skill/`docs/05-build.md`；改补丁 → 改 `patches/README.md`。
