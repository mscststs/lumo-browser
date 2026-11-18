# scripts/

所有脚本都是 `bash`（`set -euo pipefail`），**幂等、可重入**，并共享 `scripts/lib/common.sh`
（路径、日志、adb 封装、`need_device`、`resolve_out_dir`）。

```
scripts/
├── lib/          common.sh（共享库）· signing.env（签名参数）
├── chromium/     源码/依赖/工具链/补丁/构建/签名/flags/缓存/诊断
├── device/       安装/启动/扩展装载/验收/截图/APK 元信息
└── verify/       端到端验证（Lumo 侧栏 + mock OpenAI）
```

## chromium/ — 构建链路

按首次搭建顺序：

| 脚本 | 作用 | 何时用 |
|---|---|---|
| `doctor.sh` | 环境预检（源码/工具链/设备/签名/磁盘） | 第一次、换机器、构建报怪错 |
| `extract.sh` | GCS 官方 tarball → `~/chromium/src`（唯一可行的取源码方式） | 首次 / 升级版本 |
| `fetch.sh` | `gclient`/`fetch --nohistory` 取源码（**本网络不可用**，仅备用） | git smart-HTTP 可用时 |
| `cipd-deps.sh` | 装 tarball 省略的 CIPD 依赖（NDK/SDK/JDK/androidx/build-tools） | 首次 / DEPS 变化 |
| `toolchain.sh` | 拉 clang（GCS）+ 合成 `LASTCHANGE*` + 修 `gclient_args.gni` | 首次 / 升级 |
| `fix-missing-deps.sh` | 解析 `gn gen` 报错，逐个补缺失的 `//third_party/*` | `gn gen` 失败时 |
| `fetch-dep.sh` | 取单个 DEPS git 依赖（googlesource `+archive`） | 被 `fix-missing-deps` 调用 |
| `fetch-tree.sh` | 取 `chromium/src` 的某子目录（`+archive/<tag>/<path>`） | 同上 |
| `hooks.sh` | 装 apt 构建依赖 / 跑 DEPS hooks（`hooks.sh apt`） | 新系统 |
| `apply-patches.sh` | 按序 `git apply` `patches/*.patch`（sha256 stamp 幂等） | 每次构建前（build.sh 自动） |
| `patchwork.sh` | **写补丁的工具**：snapshot → 编辑 → export → revert | 新增/重做补丁 |
| `args.sh` | 打印 GN 参数（唯一出处，含签名参数） | 由 build.sh / fix-missing-deps 调用 |
| `build.sh` | 补丁 → 签名 → 品牌化 → `gn gen` → siso → 归档 APK | 日常构建 |
| `brand.sh` | 产品名 + 图标（内容比对后才写） | 由 build.sh 调用 |
| `render-icons.py` | SVG → 自适应图标三层 + 单色图标 | 由 brand.sh 调用 |
| `keys.sh` | dev 签名密钥 `install`/`status` | 构建前 / 排查签名 |
| `flags.sh` | 设备命令行唯一入口：`compose|push|show|clear|presets` | 运行时开关/扩展装载 |
| `cache.sh` | 内核身份 `manifest` + out 目录 `snapshot|restore|list` | 换机器/升级前 |

`build.sh` 的关键环境变量：`FAST`（默认 1）、`JOBS`、`OUT_DIR`、`TARGET`、`DRY_RUN`、
`SKIP_PATCHES`、`SKIP_BRAND`。

## device/ — 真机

| 脚本 | 作用 |
|---|---|
| `install.sh` | push 到 `/data/local/tmp` + `su pm install -r -g -d`（MIUI 兼容），失败回退 `adb install` |
| `apk-meta.sh` | 用 `aapt2` 读包名/入口 Activity，写 `artifacts/apk/meta.env` |
| `ext-install.sh` | 把扩展推到 `Android/data/<pkg>/files/ext`，写命令行（经 `flags.sh`），冷启动 |
| `launch.sh` | 启动并等窗口接管 |
| `shot.sh` | 截图到 `artifacts/shots/` |
| `verify.sh` | 30 项探针 + 扩展/SW + 侧栏/关闭回归，产出 `artifacts/verify/<run-id>/` 与 `GATE` |
| `run.sh` | 一条龙：install → ext-install → launch → screenshot |

## verify/ — 端到端

| 脚本 | 作用 |
|---|---|
| `lumo-e2e.sh` | 启动 `tools/mock-openai.py`，通过 CDP 在 Lumo 侧栏配置 provider 并验证流式回复；产出截图与日志 |

依赖：adb 设备、浏览器命令行带 `--remote-debugging-port=9222`、python3 `websockets`。

## 约定

- 新脚本：`#!/usr/bin/env bash` + `set -euo pipefail` + `source ../lib/common.sh`，
  文件头写清用法（`scripts/<x>.sh [args]`）与所需环境变量。
- 不要复制 `common.sh` 里的逻辑；新增共享函数放 `scripts/lib/`。
- 需要设备的脚本调用 `need_device`；只读脚本不要调用（CI 会跑）。
- 删除/重命名脚本时同步：`Makefile`、本文件、`docs/README.md`、
  `.agents/skills/*/SKILL.md`、`AGENTS.md` §3。
