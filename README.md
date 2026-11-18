# Lumo Browser

[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![chromium](https://img.shields.io/badge/chromium-160.0.8157.0-1f6feb)
![platform](https://img.shields.io/badge/android-11%2B%20arm64-3ddc84)
![mv3](https://img.shields.io/badge/MV3%20probes-30%2F30-success)

Android 上的 **Chromium 自构建浏览器**，把「完整运行 MV3 扩展」当作第一目标，
同时保持手机原生形态（底部工具栏、可拖拽侧栏、`chrome://extensions` 移动版）。

它**不是** Chromium fork：仓库里只有 **8 个最小侵入补丁** + 构建/验证工具链，
补丁按序 `git apply` 到官方 tarball 上，可随时重放、可逐条审计。

一等公民扩展（独立仓库，作为验收用例）：

| 扩展 | 覆盖的能力 |
|---|---|
| [`../lumo`](../lumo) | AI 侧栏：`sidePanel` + `scripting` + `tabs` + `webNavigation` + DNR + cookies |
| [`../lumo-userscript-manager`](../lumo-userscript-manager) | 用户脚本：`chrome.userScripts` + MAIN/USER_SCRIPT 双世界 + GM API |

## 当前状态

真机基线：Redmi K20 Pro / Android 11 / arm64 / Magisk root。
内核 `160.0.8157.0`（official，arm64），APK ≈ 343 MB，包名 `dev.lumo.browser`。

| 能力 | 状态 | 证据 |
|---|---|---|
| MV3 能力探针 | ✅ 30/30 | [`docs/07`](docs/07-capability-matrix.md) · `artifacts/verify/*/probe.json` |
| 扩展加载 + Service Worker（3 个扩展） | ✅ | `artifacts/verify/*/extensions-strings.txt` |
| `chrome://extensions` / popup / options | ✅ | 截图 |
| 手机侧栏 = 可拖拽底部抽屉（peek/收起/展开） | ✅ | `docs/04` |
| 宽屏侧栏 = 并排 + 可调宽 | ✅ | 同上 |
| 关闭侧栏不崩溃 | ✅ | `close-panel.txt` = `close_panel=ok` |
| Lumo AI 侧栏端到端（provider → 流式回复） | ✅ | [`scripts/verify/lumo-e2e.sh`](scripts/verify/lumo-e2e.sh) |
| 用户脚本注册 + 执行 | ✅ | `LUMO_USERSCRIPT_OK` |
| 验收硬门槛 | ✅ `GATE=OK` | [`docs/06`](docs/06-status.md) |

**路线状态（诚实版）**

| 配置 | args.gn 关键项 | 状态 |
|---|---|---|
| `a`（当前构建、已验收） | `is_desktop_android = true` | ✅ 真机 30/30、侧栏、扩展全部通过 |
| `b`（手机原生 UI + 扩展核心） | `target_os="android"` + `enable_desktop_android_extensions=true` | ⛔ **实测不可直接编译**：`gn gen` 被上游断言拦住（`assert(enable_webui_ntp)` → WebUI 资源要求 `is_desktop_android`），需要专属补丁子集；详见 [`docs/00` §5](docs/00-strategy-and-start.md) |

## 快速开始

前置：Linux x86_64、≥12 核 / ≥32 GB 内存、≥120 GB 磁盘、`adb` 与 root 设备（可选）。
环境自检：

```bash
scripts/chromium/doctor.sh
```

```bash
# 1) 源码（官方 GCS tarball；本网络无法用 googlesource git）
mkdir -p artifacts/src
curl -L -o artifacts/src/chromium-160.0.8157.0.tar.xz \
  https://commondatastorage.googleapis.com/chromium-browser-official/chromium-160.0.8157.0.tar.xz
scripts/chromium/extract.sh artifacts/src/chromium-160.0.8157.0.tar.xz

# 2) 依赖与工具链（CIPD 的 NDK/SDK/JDK/androidx + clang + LASTCHANGE）
scripts/chromium/cipd-deps.sh
scripts/chromium/toolchain.sh
#    gn gen 报缺少某个 //third_party/... 时：
#   scripts/chromium/fix-missing-deps.sh a

# 3) 构建（首次数小时；之后增量 25 s – 2 min）
scripts/chromium/build.sh a

# 4) 装机 + 装载扩展 + 验收（产出 artifacts/verify/<run-id>/）
scripts/device/install.sh
scripts/device/ext-install.sh
scripts/device/verify.sh

# 5) 端到端：Lumo 侧栏 + 本地 mock OpenAI（需要 --remote-debugging-port=9222）
scripts/verify/lumo-e2e.sh
```

`make help` 是这些命令的另一种入口（等价目标）。首次只想要一个能跑的包：

```bash
make apk && make install
```

## 迭代：内核不是每次都要编

分三层，只有第三层需要编译器（完整数据与实测见 [`docs/09`](docs/09-build-iteration.md)）：

| 层 | 例子 | 做法 | 编内核 |
|---|---|---|---|
| 扩展层 | AI 侧栏、用户脚本、拦截规则 | 扩展仓库 `npm run build` → `scripts/device/ext-install.sh` | ❌ |
| 运行时开关 | 侧栏开关/拖宽、日志、实验特性 | `scripts/chromium/flags.sh` | ❌ |
| 结构性补丁 | 手机工具栏承载点、bottom sheet、popup 锚点 | `patches/NNNN-*.patch` → `build.sh` | ✅ |

实测成本（12 核）：C++ 补丁 25 s、Java 补丁 ~2 min、`build.sh` 空跑 19 s、全量 2–4 h。

```bash
scripts/chromium/flags.sh presets                       # 可运行时切换的 feature
LUMO_DISABLE_FEATURES=EnableAndroidSidePanel \
  scripts/chromium/flags.sh push                        # 关掉侧栏做回归，不重编译
scripts/chromium/cache.sh manifest                      # 记录内核身份（换版本/换机器时对照）
scripts/chromium/cache.sh snapshot                      # 归档 out/ 目录（跨机器复用编译缓存）
```

## 目录结构

```
├── .agents/skills/          一线 agent 工作手册（构建 / 补丁 / 真机验证）
├── .github/                 CI（静态检查 + 仓库卫生）与 PR 模板
├── keys/                    dev 签名密钥（公开、仅 debug，见 keys/README.md）
├── patches/                 按序应用的 Chromium 补丁（NNNN-*.patch）+ 状态表
├── scripts/
│   ├── chromium/            取源码、依赖、工具链、打补丁、构建、签名、flags、缓存
│   ├── device/              安装、启动、扩展装载、验收、截图
│   ├── verify/              端到端验证（Lumo 侧栏 + mock OpenAI）
│   └── lib/                 共享 shell 库（common.sh / signing.env）
├── tools/                   CDP、探针扩展、mock server、仓库检查
├── docs/                    架构 / 验收 / 能力矩阵 / 决策记录（ADR）
└── artifacts/               （gitignored）APK、验证证据、缓存 manifest
```

Chromium 源码放在 `~/chromium/src`（仓库外），每个构建 flavor 独占一个 `out/<dir>`。

## 文档

完整索引见 [`docs/README.md`](docs/README.md)：

| 想知道 | 看 |
|---|---|
| 怎么构建、为什么这么慢、如何不重编内核 | [`docs/09-build-iteration.md`](docs/09-build-iteration.md) |
| 架构、上游扩展 UI 现状、无 git 的依赖链 | [`docs/01-architecture.md`](docs/01-architecture.md) |
| 验收流程与判定口径 | [`docs/03-verification.md`](docs/03-verification.md) |
| MV3 能力矩阵（30 项实测） | [`docs/07-capability-matrix.md`](docs/07-capability-matrix.md) |
| 当前状态与证据 | [`docs/06-status.md`](docs/06-status.md) |
| 侧栏形态与用户脚本开关的设计 | [`docs/04-sidepanel-and-userscripts.md`](docs/04-sidepanel-and-userscripts.md) |
| GPU/ANGLE 排查 | [`docs/05-gpu-notes.md`](docs/05-gpu-notes.md) |
| 安全决策与残留风险 | [`docs/08-security-and-hardening.md`](docs/08-security-and-hardening.md) + [`SECURITY.md`](SECURITY.md) |
| 补丁规则与清单 | [`patches/README.md`](patches/README.md) |
| 关键决策（ADR） | [`docs/adr/`](docs/adr/README.md) |

## 明确不支持

平台限制，补丁解决不了，**不要**写进发布说明：

- `nativeMessaging`（Android 需要独立宿主进程）
- `desktopCapture` / `tabCapture` 的采集源语义（Android 无对应源）
- `devtools.*` 面板、`enterprise.*`、平台应用（`app.*`）
- `chrome.windows` 的多窗口完整语义

## 签名

APK 使用仓库内的 **dev key** 签名（`keys/lumo-dev.jks`，故意入库）：

- 好处：`pm install -r` 可覆盖升级，profile / 扩展 / 用户脚本开关不丢。
- 代价：**它是公开的** —— 任何人可签同名同证书的包，签名不代表来源可信。
- 只用于 debug/自测；正式分发需另建 release key（不入库，走 CI secret）。
- 校验官方包请比对 `artifacts/cache/kernel-*.txt` 里的 `apk sha256`。

细节与证书指纹：[`keys/README.md`](keys/README.md)。

## 许可

本仓库（脚本、补丁、文档、工具）：**MIT**，见 [`LICENSE`](LICENSE)。
`patches/` 是对 Chromium 源文件的修改，其 hunks 仍属 Chromium 的 **BSD-3-Clause**；
Chromium 源码不在本仓库分发。详见 [`NOTICE`](NOTICE)。

贡献流程见 [`CONTRIBUTING.md`](CONTRIBUTING.md)，安全问题见 [`SECURITY.md`](SECURITY.md)。
